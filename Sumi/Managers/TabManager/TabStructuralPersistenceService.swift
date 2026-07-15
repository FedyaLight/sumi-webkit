import Foundation

/// Persists structural tab state through serialized incremental writes and the
/// explicit full-reconcile paths used by restore, repair, and termination.
@MainActor
final class TabStructuralPersistenceService {
    private enum StructuralPersistencePayload: Sendable {
        case incremental(TabStructuralPersistenceDelta, TabStructuralDirtySet, Int)
        case fullReconcile(String)
    }

    private let structuralStore: TabStructuralSnapshotStore
    private let selectionStore: TabSelectionStore
    private let runtimeStateCoalescer: RuntimeStateCoalescer
    private let state: TabStateStore
    private let debounceNanoseconds: UInt64

    private(set) var dirtySet = TabStructuralDirtySet()
    private var snapshotCache = TabStructuralSnapshotCache()
    private var persistenceGeneration = 0
    private(set) var scheduledPersistTask: Task<Void, Never>?
    private(set) var selectionPersistTask: Task<Void, Never>?
    private var persistRequestID: UInt64 = 0

    /// Monotonic scheduling/cancellation boundary used by exact transaction
    /// oracles. A rejected structural operation must not advance it.
    var schedulingRevision: UInt64 { persistRequestID }

    init(
        structuralStore: TabStructuralSnapshotStore,
        selectionStore: TabSelectionStore,
        runtimeStateCoalescer: RuntimeStateCoalescer,
        debounceNanoseconds: UInt64 = 250_000_000,
        state: TabStateStore
    ) {
        self.structuralStore = structuralStore
        self.selectionStore = selectionStore
        self.runtimeStateCoalescer = runtimeStateCoalescer
        self.debounceNanoseconds = debounceNanoseconds
        self.state = state
    }

    deinit {
        MainActor.assumeIsolated {
            scheduledPersistTask?.cancel()
            scheduledPersistTask = nil
        }
    }

    // MARK: - Scheduling

    func scheduleStructuralPersistence() {
        scheduleStructuralPersistenceOnMain()
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

    func cancelPendingPersistence() {
        cancelScheduledStructuralPersistence()
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
            let didPersist = await structuralStore.persistIncremental(
                delta: delta,
                generation: generation
            )
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

        let payload: (TabPersistenceSnapshot, Int)? = await MainActor.run { [weak self] in
            guard let strong = self else { return nil }
            let generation = strong.nextPersistenceGeneration()
            let snapshot = strong.buildSnapshot()
            return (snapshot, generation)
        }
        guard let (snapshot, generation) = payload else {
            return false
        }
        let didPersist = await structuralStore.persistFullReconcile(
            snapshot: snapshot,
            generation: generation
        )
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
        let spaceID = state.spaces.currentSpaceId
        let precedingPersist = selectionPersistTask
        selectionPersistTask = Task { [selectionStore] in
            await precedingPersist?.value
            let signpostState = PerformanceTrace.beginInterval("TabManager.persistSelection")
            defer {
                PerformanceTrace.endInterval("TabManager.persistSelection", signpostState)
            }
            await selectionStore.persist(currentTabID: tabID, currentSpaceID: spaceID)
        }
    }

    func scheduleRuntimeStatePersistence(for tab: Tab) {
        guard shouldPersistRegularTab(tab) else { return }

        if let spaceId = tab.spaceId {
            markRegularTabsSnapshotDirty(for: spaceId)
        }

        let payload = TabRuntimeStateUpdate(
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
        guard ExtensionURLIdentity.isOwned(tab.url) == false else { return false }
        return true
    }

    func persistableCurrentTabID() -> UUID? {
        guard let currentTab = state.selection.currentTab,
              shouldPersistRegularTab(currentTab) else {
            return nil
        }
        return currentTab.id
    }

    // MARK: - Snapshot Construction

    func buildSnapshot() -> TabPersistenceSnapshot {
        PerformanceTrace.withInterval("TabManager._buildSnapshot") {
            snapshotCache.makeSnapshot(from: makeSnapshotSource())
        }
    }

    private func buildStructuralDelta(
        from dirtySet: TabStructuralDirtySet
    ) -> TabStructuralPersistenceDelta {
        TabStructuralSnapshotMaterializer().makeStructuralDelta(
            from: dirtySet,
            spaces: state.spaces.spaces,
            pinnedByProfile: state.shortcutPins.pinnedByProfileSnapshot(),
            spacePinnedShortcuts: state.shortcutPins.spacePinnedShortcutsSnapshot(),
            tabsBySpace: state.regularTabs.tabsBySpaceSnapshot(),
            foldersBySpace: state.folders.foldersBySpaceSnapshot(),
            splitGroups: state.splitGroups.groups,
            currentTabId: persistableCurrentTabID(),
            currentSpaceId: state.spaces.currentSpaceId,
            shouldPersistRegularTab: shouldPersistRegularTab
        )
    }

    private func makeSnapshotSource() -> TabStructuralSnapshotSource {
        TabStructuralSnapshotSource(
            spaces: state.spaces.spaces,
            splitGroups: state.splitGroups.groups,
            pinnedByProfile: state.shortcutPins.pinnedByProfileSnapshot(),
            spacePinnedShortcuts: state.shortcutPins.spacePinnedShortcutsSnapshot(),
            tabsBySpace: state.regularTabs.tabsBySpaceSnapshot(),
            foldersBySpace: state.folders.foldersBySpaceSnapshot(),
            currentTabId: persistableCurrentTabID(),
            currentSpaceId: state.spaces.currentSpaceId,
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
        dirtySet.markSpacesDirty(state.spaces.spaces.map(\.id))
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
        dirtySet.markTabsDirty(
            (state.regularTabs.tabsBySpaceSnapshot()[spaceId] ?? []).map(\.id)
        )
    }

    func markFoldersSnapshotDirty(for spaceId: UUID) {
        snapshotCache.invalidateFolders(spaceId: spaceId)
    }

    func markFoldersStructurallyDirty(for spaceId: UUID) {
        markFoldersSnapshotDirty(for: spaceId)
        dirtySet.markFoldersDirty(
            (state.folders.foldersBySpaceSnapshot()[spaceId] ?? []).map(\.id)
        )
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
