import Foundation

/// Owns structural tab persistence: dirty tracking, snapshot caching, debounced
/// scheduling, incremental deltas, and the full-reconcile fallback path.
@MainActor
final class TabStructuralPersistenceOwner {
    struct Dependencies {
        let spaces: @MainActor () -> [Space]
        let splitGroups: @MainActor () -> [SplitGroup]
        let pinnedByProfile: @MainActor () -> [UUID: [ShortcutPin]]
        let spacePinnedShortcuts: @MainActor () -> [UUID: [ShortcutPin]]
        let tabsBySpace: @MainActor () -> [UUID: [Tab]]
        let foldersBySpace: @MainActor () -> [UUID: [TabFolder]]
        let currentSpaceId: @MainActor () -> UUID?
        let currentTab: @MainActor () -> Tab?
        let reconcileProfileRuntimeStates: @MainActor (_ activeSpaceId: UUID?) -> Void
    }

    private enum StructuralPersistencePayload: Sendable {
        case incremental(TabSnapshotRepository.StructuralDelta, TabStructuralDirtySet, Int)
        case fullReconcile(String)
    }

    private let persistence: TabSnapshotRepository
    private let runtimeStateCoalescer: RuntimeStateCoalescer
    private let debounceNanoseconds: UInt64
    private let dependencies: Dependencies

    private(set) var dirtySet = TabStructuralDirtySet()
    private var snapshotCache = TabStructuralSnapshotCache()
    private var persistenceGeneration = 0
    private(set) var scheduledPersistTask: Task<Void, Never>?
    private var persistRequestID: UInt64 = 0

    init(
        persistence: TabSnapshotRepository,
        runtimeStateCoalescer: RuntimeStateCoalescer,
        debounceNanoseconds: UInt64 = 250_000_000,
        dependencies: Dependencies
    ) {
        self.persistence = persistence
        self.runtimeStateCoalescer = runtimeStateCoalescer
        self.debounceNanoseconds = debounceNanoseconds
        self.dependencies = dependencies
    }

    deinit {
        MainActor.assumeIsolated {
            scheduledPersistTask?.cancel()
            scheduledPersistTask = nil
        }
    }

    // MARK: - Scheduling

    nonisolated func scheduleStructuralPersistence() {
        Task { @MainActor [weak self] in
            self?.scheduleStructuralPersistenceOnMain()
        }
    }

    func scheduleStructuralPersistenceFromMain() {
        scheduleStructuralPersistenceOnMain()
    }

    /// Explicit full reconcile path for restore, repair, fallback, and termination only.
    nonisolated func persistFullReconcileAwaitingResult(reason: String) async -> Bool {
        await MainActor.run { [weak self] in
            self?.cancelScheduledStructuralPersistence()
        }
        return await performFullReconcileNow(reason: reason)
    }

    private func scheduleStructuralPersistenceOnMain() {
        persistRequestID &+= 1
        let requestID = persistRequestID
        let debounceDelay = debounceNanoseconds

        scheduledPersistTask?.cancel()
        scheduledPersistTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
            } catch {
                return
            }

            await self?.executeScheduledStructuralPersistence(requestID: requestID)
        }
    }

    private func cancelScheduledStructuralPersistence() {
        persistRequestID &+= 1
        scheduledPersistTask?.cancel()
        scheduledPersistTask = nil
    }

    private func executeScheduledStructuralPersistence(requestID: UInt64) async {
        guard persistRequestID == requestID else { return }
        scheduledPersistTask = nil
        _ = await persistIncrementalStructuralNow()
    }

    private nonisolated func persistIncrementalStructuralNow() async -> Bool {
        let signpostState = PerformanceTrace.beginInterval("TabManager.persistIncrementalStructuralNow")
        defer {
            PerformanceTrace.endInterval("TabManager.persistIncrementalStructuralNow", signpostState)
        }

        let payload: StructuralPersistencePayload? = await MainActor.run { [weak self] in
            guard let strong = self else { return nil }
            guard strong.dirtySet.isEmpty == false else { return nil }

            if let reason = strong.dirtySet.needsFullReconcileReason {
                strong.dirtySet = TabStructuralDirtySet()
                return .fullReconcile(reason)
            }

            let pending = strong.dirtySet.takePending()
            guard pending.hasIncrementalChanges else { return nil }

            let generation = strong.nextPersistenceGeneration()
            let delta = strong.buildStructuralDelta(from: pending)
            return .incremental(delta, pending, generation)
        }

        guard let payload else {
            return true
        }

        switch payload {
        case .fullReconcile(let reason):
            return await performFullReconcileNow(reason: reason)
        case .incremental(let delta, let consumedDirtySet, let generation):
            let didPersist = await persistence.persistIncremental(delta: delta, generation: generation)
            if didPersist {
                return true
            }

            await MainActor.run { [weak self] in
                self?.dirtySet.merge(consumedDirtySet)
                self?.dirtySet.requestFullReconcile(
                    reason: "incremental structural persistence failed"
                )
            }
            return await performFullReconcileNow(reason: "incremental structural persistence failed")
        }
    }

    @discardableResult
    nonisolated func flushRuntimeStatePersistenceAwaitingResult() async -> Int {
        await runtimeStateCoalescer.flushImmediately()
    }

    private nonisolated func performFullReconcileNow(reason _: String) async -> Bool {
        _ = await flushRuntimeStatePersistenceAwaitingResult()

        let signpostState = PerformanceTrace.beginInterval("TabManager.performFullReconcileNow")
        defer {
            PerformanceTrace.endInterval("TabManager.performFullReconcileNow", signpostState)
        }

        let payload: (TabSnapshotRepository.Snapshot, Int)? = await MainActor.run { [weak self] in
            guard let strong = self else { return nil }
            let generation = strong.nextPersistenceGeneration()
            let snapshot = strong.buildSnapshot()
            return (snapshot, generation)
        }
        guard let (snapshot, generation) = payload else {
            return false
        }
        let didPersist = await persistence.persistFullReconcile(snapshot: snapshot, generation: generation)
        if didPersist {
            await MainActor.run { [weak self] in
                self?.dirtySet = TabStructuralDirtySet()
            }
        }
        return didPersist
    }

    // MARK: - Selection and Runtime State

    /// Lightweight persistence for tab selection changes only.
    /// Avoids rebuilding the full snapshot graph when only currentTabID/currentSpaceID changed.
    func persistSelection() {
        let tabID = persistableCurrentTabID()
        let spaceID = dependencies.currentSpaceId()
        Task { [persistence] in
            let signpostState = PerformanceTrace.beginInterval("TabManager.persistSelection")
            defer {
                PerformanceTrace.endInterval("TabManager.persistSelection", signpostState)
            }
            await persistence.persistSelectionOnly(currentTabID: tabID, currentSpaceID: spaceID)
        }
    }

    func scheduleRuntimeStatePersistence(for tab: Tab) {
        guard shouldPersistRegularTab(tab) else { return }

        if let spaceId = tab.spaceId {
            markRegularTabsSnapshotDirty(for: spaceId)
        }

        let payload = TabSnapshotRepository.RuntimeTabState(
            id: tab.id,
            urlString: tab.url.absoluteString,
            currentURLString: tab.url.absoluteString,
            name: tab.name,
            canGoBack: tab.canGoBack,
            canGoForward: tab.canGoForward
        )
        runtimeStateCoalescer.enqueue(payload)
    }

    func cancelRuntimeStatePersistence(for tabId: UUID) {
        runtimeStateCoalescer.cancel(tabID: tabId)
    }

    // MARK: - Persistence Policy

    func shouldPersistRegularTab(_ tab: Tab) -> Bool {
        guard tab.isEphemeral == false else { return false }
        guard tab.isShortcutLiveInstance == false else { return false }
        guard tab.isPinned == false, tab.isSpacePinned == false else { return false }
        guard tab.spaceId != nil else { return false }
        guard ExtensionUtils.isExtensionOwnedURL(tab.url) == false else { return false }
        return true
    }

    func persistableCurrentTabID() -> UUID? {
        guard let currentTab = dependencies.currentTab(), shouldPersistRegularTab(currentTab) else {
            return nil
        }
        return currentTab.id
    }

    // MARK: - Snapshot Construction

    func buildSnapshot() -> TabSnapshotRepository.Snapshot {
        PerformanceTrace.withInterval("TabManager._buildSnapshot") {
            dependencies.reconcileProfileRuntimeStates(dependencies.currentSpaceId())
            return snapshotCache.makeSnapshot(from: makeSnapshotSource())
        }
    }

    private func buildStructuralDelta(
        from dirtySet: TabStructuralDirtySet
    ) -> TabSnapshotRepository.StructuralDelta {
        TabStructuralSnapshotMaterializer().makeStructuralDelta(
            from: dirtySet,
            spaces: dependencies.spaces(),
            pinnedByProfile: dependencies.pinnedByProfile(),
            spacePinnedShortcuts: dependencies.spacePinnedShortcuts(),
            tabsBySpace: dependencies.tabsBySpace(),
            foldersBySpace: dependencies.foldersBySpace(),
            splitGroups: dependencies.splitGroups(),
            currentTabId: persistableCurrentTabID(),
            currentSpaceId: dependencies.currentSpaceId(),
            shouldPersistRegularTab: shouldPersistRegularTab
        )
    }

    private func makeSnapshotSource() -> TabStructuralSnapshotSource {
        TabStructuralSnapshotSource(
            spaces: dependencies.spaces(),
            splitGroups: dependencies.splitGroups(),
            pinnedByProfile: dependencies.pinnedByProfile(),
            spacePinnedShortcuts: dependencies.spacePinnedShortcuts(),
            tabsBySpace: dependencies.tabsBySpace(),
            foldersBySpace: dependencies.foldersBySpace(),
            currentTabId: persistableCurrentTabID(),
            currentSpaceId: dependencies.currentSpaceId(),
            shouldPersistRegularTab: shouldPersistRegularTab
        )
    }

    private func nextPersistenceGeneration() -> Int {
        persistenceGeneration &+= 1
        return persistenceGeneration
    }

    /// Reserves a persistence generation for callers that persist outside the
    /// scheduled paths (restore repair, startup policy).
    func reservePersistenceGeneration() -> Int {
        nextPersistenceGeneration()
    }

    // MARK: - Dirty Tracking

    func markSnapshotCacheDirty() {
        snapshotCache.invalidateAll()
    }

    func markSpacesSnapshotDirty() {
        snapshotCache.invalidateSpaces()
    }

    func markAllSpacesStructurallyDirty() {
        markSpacesSnapshotDirty()
        dirtySet.markSpacesDirty(dependencies.spaces().map(\.id))
    }

    func markSpaceStructurallyDeleted(_ spaceId: UUID) {
        dirtySet.markSpacesDeleted([spaceId])
    }

    func markPinnedSnapshotDirty(for profileId: UUID) {
        snapshotCache.invalidatePinned(profileId: profileId)
    }

    func markSpacePinnedSnapshotDirty(for spaceId: UUID) {
        snapshotCache.invalidateSpacePinned(spaceId: spaceId)
    }

    func markRegularTabsSnapshotDirty(for spaceId: UUID) {
        snapshotCache.invalidateRegularTabs(spaceId: spaceId)
    }

    func markRegularTabsStructurallyDirty(for spaceId: UUID) {
        markRegularTabsSnapshotDirty(for: spaceId)
        dirtySet.markTabsDirty((dependencies.tabsBySpace()[spaceId] ?? []).map(\.id))
    }

    func markFoldersSnapshotDirty(for spaceId: UUID) {
        snapshotCache.invalidateFolders(spaceId: spaceId)
    }

    func markFoldersStructurallyDirty(for spaceId: UUID) {
        markFoldersSnapshotDirty(for: spaceId)
        dirtySet.markFoldersDirty((dependencies.foldersBySpace()[spaceId] ?? []).map(\.id))
    }

    func markSplitGroupsStructurallyDirty() {
        dirtySet.markSplitGroupsDirty()
        snapshotCache.invalidateSplitGroups()
    }

    func resetDirtySet() {
        dirtySet = TabStructuralDirtySet()
    }

    /// Resets scheduling and dirty state after restored data replaced the live structure.
    func prepareForRestoredState() {
        markSnapshotCacheDirty()
        resetDirtySet()
        cancelScheduledStructuralPersistence()
    }

    func recordRegularTabsStructuralChange(previous: [Tab], current: [Tab]) {
        let previousIds = Set(previous.map(\.id))
        let currentIds = Set(current.map(\.id))
        dirtySet.markTabsDeleted(previousIds.subtracting(currentIds))
        dirtySet.markTabsDirty(current.map(\.id))
    }

    func recordFoldersStructuralChange(previous: [TabFolder], current: [TabFolder]) {
        let previousIds = Set(previous.map(\.id))
        let currentIds = Set(current.map(\.id))
        dirtySet.markFoldersDeleted(previousIds.subtracting(currentIds))
        dirtySet.markFoldersDirty(current.map(\.id))
    }

    func recordShortcutPinsStructuralChange(previous: [ShortcutPin], current: [ShortcutPin]) {
        let previousIds = Set(previous.map(\.id))
        let currentIds = Set(current.map(\.id))
        dirtySet.markTabsDeleted(previousIds.subtracting(currentIds))
        dirtySet.markTabsDirty(current.map(\.id))
    }
}

extension TabStructuralPersistenceOwner.Dependencies {
    @MainActor
    static func live(tabManager: TabManager) -> Self {
        Self(
            spaces: { [weak tabManager] in tabManager?.spaceStateOwner.spaces ?? [] },
            splitGroups: { [weak tabManager] in tabManager?.splitGroupCollectionStateOwner.splitGroups ?? [] },
            pinnedByProfile: { [weak tabManager] in tabManager?.shortcutPinCollectionStateOwner.pinnedByProfileSnapshot() ?? [:] },
            spacePinnedShortcuts: { [weak tabManager] in tabManager?.shortcutPinCollectionStateOwner.spacePinnedShortcutsSnapshot() ?? [:] },
            tabsBySpace: { [weak tabManager] in tabManager?.regularTabCollectionStateOwner.tabsBySpaceSnapshot() ?? [:] },
            foldersBySpace: { [weak tabManager] in tabManager?.folderCollectionStateOwner.foldersBySpaceSnapshot() ?? [:] },
            currentSpaceId: { [weak tabManager] in tabManager?.spaceStateOwner.currentSpace?.id },
            currentTab: { [weak tabManager] in tabManager?.selectionStateOwner.currentTab },
            reconcileProfileRuntimeStates: { [weak tabManager] activeSpaceId in
                tabManager?.profileRuntimeStateOwner.reconcile(activeSpaceId: activeSpaceId)
            }
        )
    }
}
