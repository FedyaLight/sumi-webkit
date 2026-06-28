import AppKit
import Foundation
import SwiftData

@MainActor
struct TabManagerSnapshotCache {
    private typealias SnapshotSpace = TabSnapshotRepository.SnapshotSpace
    private typealias SnapshotTab = TabSnapshotRepository.SnapshotTab
    private typealias SnapshotFolder = TabSnapshotRepository.SnapshotFolder

    private var spaceSnapshots: [SnapshotSpace] = []
    private var splitGroupSnapshots: [SplitGroup] = []
    private var pinnedTabsByProfile: [UUID: [SnapshotTab]] = [:]
    private var spacePinnedTabsBySpace: [UUID: [SnapshotTab]] = [:]
    private var regularTabsBySpace: [UUID: [SnapshotTab]] = [:]
    private var folderSnapshotsBySpace: [UUID: [SnapshotFolder]] = [:]
    private let materializer = TabStructuralSnapshotMaterializer()

    private var spacesDirty = true
    private var splitGroupsDirty = true
    private var dirtyPinnedProfileIds: Set<UUID> = []
    private var dirtySpacePinnedSpaceIds: Set<UUID> = []
    private var dirtyRegularTabSpaceIds: Set<UUID> = []
    private var dirtyFolderSpaceIds: Set<UUID> = []

    mutating func invalidateAll() {
        spacesDirty = true
        splitGroupsDirty = true
        dirtyPinnedProfileIds = []
        dirtySpacePinnedSpaceIds = []
        dirtyRegularTabSpaceIds = []
        dirtyFolderSpaceIds = []
        pinnedTabsByProfile.removeAll(keepingCapacity: true)
        spacePinnedTabsBySpace.removeAll(keepingCapacity: true)
        regularTabsBySpace.removeAll(keepingCapacity: true)
        folderSnapshotsBySpace.removeAll(keepingCapacity: true)
    }

    mutating func invalidateSpaces() {
        spacesDirty = true
    }

    mutating func invalidateSplitGroups() {
        splitGroupsDirty = true
    }

    mutating func invalidatePinned(profileId: UUID) {
        dirtyPinnedProfileIds.insert(profileId)
    }

    mutating func invalidateSpacePinned(spaceId: UUID) {
        dirtySpacePinnedSpaceIds.insert(spaceId)
    }

    mutating func invalidateRegularTabs(spaceId: UUID) {
        dirtyRegularTabSpaceIds.insert(spaceId)
    }

    mutating func invalidateFolders(spaceId: UUID) {
        dirtyFolderSpaceIds.insert(spaceId)
    }

    mutating func makeSnapshot(for tabManager: TabManager) -> TabSnapshotRepository.Snapshot {
        tabManager.reconcileProfileRuntimeStates(activeSpaceId: tabManager.currentSpace?.id)

        let orderedSpaces = tabManager.spaces
        let liveSpaceIds = Set(orderedSpaces.map(\.id))

        if spacesDirty {
            spaceSnapshots = materializer.makeSpaceSnapshots(spaces: orderedSpaces)
            spacesDirty = false
        }
        if splitGroupsDirty {
            splitGroupSnapshots = materializer.makeSplitGroupSnapshots(tabManager.splitGroups)
            splitGroupsDirty = false
        }

        refreshPinnedTabs(using: tabManager)
        refreshSpacePinnedTabs(using: tabManager, liveSpaceIds: liveSpaceIds)
        refreshRegularTabs(using: tabManager, liveSpaceIds: liveSpaceIds)
        refreshFolders(using: tabManager, liveSpaceIds: liveSpaceIds)

        var tabSnapshots: [SnapshotTab] = []
        tabSnapshots.reserveCapacity(
            pinnedTabsByProfile.values.reduce(0) { $0 + $1.count }
                + spacePinnedTabsBySpace.values.reduce(0) { $0 + $1.count }
                + regularTabsBySpace.values.reduce(0) { $0 + $1.count }
        )

        for profileId in tabManager.pinnedByProfile.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            tabSnapshots.append(contentsOf: pinnedTabsByProfile[profileId] ?? [])
        }
        for space in orderedSpaces {
            tabSnapshots.append(contentsOf: spacePinnedTabsBySpace[space.id] ?? [])
            tabSnapshots.append(contentsOf: regularTabsBySpace[space.id] ?? [])
        }

        var folderSnapshots: [SnapshotFolder] = []
        folderSnapshots.reserveCapacity(folderSnapshotsBySpace.values.reduce(0) { $0 + $1.count })
        for space in orderedSpaces {
            folderSnapshots.append(contentsOf: folderSnapshotsBySpace[space.id] ?? [])
        }

        return materializer.makeSnapshot(
            spaces: spaceSnapshots,
            tabs: tabSnapshots,
            folders: folderSnapshots,
            splitGroups: splitGroupSnapshots,
            currentTabId: tabManager.persistableCurrentTabID(),
            currentSpaceId: tabManager.currentSpace?.id
        )
    }

    private mutating func refreshPinnedTabs(using tabManager: TabManager) {
        let liveProfileIds = Set(tabManager.pinnedByProfile.keys)
        pinnedTabsByProfile = pinnedTabsByProfile.filter { liveProfileIds.contains($0.key) }

        let profileIdsToRefresh: Set<UUID>
        if pinnedTabsByProfile.isEmpty, liveProfileIds.isEmpty == false {
            profileIdsToRefresh = liveProfileIds
        } else {
            profileIdsToRefresh = dirtyPinnedProfileIds
        }

        for profileId in profileIdsToRefresh {
            let pins = Array(tabManager.pinnedByProfile[profileId] ?? [])
            pinnedTabsByProfile[profileId] = materializer.makePinnedTabSnapshots(
                profileId: profileId,
                pins: pins
            )
        }
        dirtyPinnedProfileIds.removeAll(keepingCapacity: true)
    }

    private mutating func refreshSpacePinnedTabs(
        using tabManager: TabManager,
        liveSpaceIds: Set<UUID>
    ) {
        spacePinnedTabsBySpace = spacePinnedTabsBySpace.filter { liveSpaceIds.contains($0.key) }

        let liveIds = Set(tabManager.spacePinnedShortcuts.keys)
        let missingIds = liveIds.subtracting(spacePinnedTabsBySpace.keys)
        let refreshIds = dirtySpacePinnedSpaceIds.union(missingIds)
        for spaceId in refreshIds {
            guard liveSpaceIds.contains(spaceId) else {
                spacePinnedTabsBySpace.removeValue(forKey: spaceId)
                continue
            }
            let shortcutPins = Array(tabManager.spacePinnedShortcuts[spaceId] ?? [])
            spacePinnedTabsBySpace[spaceId] = materializer.makeSpacePinnedTabSnapshots(
                spaceId: spaceId,
                pins: shortcutPins
            )
        }
        dirtySpacePinnedSpaceIds.removeAll(keepingCapacity: true)
    }

    private mutating func refreshRegularTabs(
        using tabManager: TabManager,
        liveSpaceIds: Set<UUID>
    ) {
        regularTabsBySpace = regularTabsBySpace.filter { liveSpaceIds.contains($0.key) }

        let liveIds = Set(tabManager.tabsBySpace.keys)
        let missingIds = liveIds.subtracting(regularTabsBySpace.keys)
        let refreshIds = dirtyRegularTabSpaceIds.union(missingIds)
        for spaceId in refreshIds {
            guard liveSpaceIds.contains(spaceId) else {
                regularTabsBySpace.removeValue(forKey: spaceId)
                continue
            }
            let regularTabs = Array(tabManager.tabsBySpace[spaceId] ?? [])
            regularTabsBySpace[spaceId] = materializer.makeRegularTabSnapshots(
                spaceId: spaceId,
                tabs: regularTabs,
                shouldPersistRegularTab: tabManager.shouldPersistRegularTab
            )
        }
        dirtyRegularTabSpaceIds.removeAll(keepingCapacity: true)
    }

    private mutating func refreshFolders(
        using tabManager: TabManager,
        liveSpaceIds: Set<UUID>
    ) {
        folderSnapshotsBySpace = folderSnapshotsBySpace.filter { liveSpaceIds.contains($0.key) }

        let liveIds = Set(tabManager.foldersBySpace.keys)
        let missingIds = liveIds.subtracting(folderSnapshotsBySpace.keys)
        let refreshIds = dirtyFolderSpaceIds.union(missingIds)
        for spaceId in refreshIds {
            guard liveSpaceIds.contains(spaceId) else {
                folderSnapshotsBySpace.removeValue(forKey: spaceId)
                continue
            }
            let folders = tabManager.foldersBySpace[spaceId] ?? []
            folderSnapshotsBySpace[spaceId] = materializer.makeFolderSnapshots(
                spaceId: spaceId,
                folders: folders
            )
        }
        dirtyFolderSpaceIds.removeAll(keepingCapacity: true)
    }
}

struct TabStructuralDirtySet: Sendable {
    var dirtyTabIds: Set<UUID> = []
    var dirtyFolderIds: Set<UUID> = []
    var dirtySpaceIds: Set<UUID> = []
    var deletedTabIds: Set<UUID> = []
    var deletedFolderIds: Set<UUID> = []
    var deletedSpaceIds: Set<UUID> = []
    var splitGroupsDirty = false
    var needsFullReconcileReason: String?

    var isEmpty: Bool {
        dirtyTabIds.isEmpty
            && dirtyFolderIds.isEmpty
            && dirtySpaceIds.isEmpty
            && deletedTabIds.isEmpty
            && deletedFolderIds.isEmpty
            && deletedSpaceIds.isEmpty
            && splitGroupsDirty == false
            && needsFullReconcileReason == nil
    }

    var hasIncrementalChanges: Bool {
        dirtyTabIds.isEmpty == false
            || dirtyFolderIds.isEmpty == false
            || dirtySpaceIds.isEmpty == false
            || deletedTabIds.isEmpty == false
            || deletedFolderIds.isEmpty == false
            || deletedSpaceIds.isEmpty == false
            || splitGroupsDirty
    }

    mutating func markTabsDirty<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            deletedTabIds.remove(id)
            dirtyTabIds.insert(id)
        }
    }

    mutating func markFoldersDirty<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            deletedFolderIds.remove(id)
            dirtyFolderIds.insert(id)
        }
    }

    mutating func markSpacesDirty<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            deletedSpaceIds.remove(id)
            dirtySpaceIds.insert(id)
        }
    }

    mutating func markTabsDeleted<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            dirtyTabIds.remove(id)
            deletedTabIds.insert(id)
        }
    }

    mutating func markFoldersDeleted<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            dirtyFolderIds.remove(id)
            deletedFolderIds.insert(id)
        }
    }

    mutating func markSpacesDeleted<S: Sequence>(_ ids: S) where S.Element == UUID {
        for id in ids {
            dirtySpaceIds.remove(id)
            deletedSpaceIds.insert(id)
        }
    }

    mutating func markSplitGroupsDirty() {
        splitGroupsDirty = true
    }

    mutating func requestFullReconcile(reason: String) {
        if needsFullReconcileReason == nil {
            needsFullReconcileReason = reason
        }
    }

    mutating func takePending() -> TabStructuralDirtySet {
        let pending = self
        self = TabStructuralDirtySet()
        return pending
    }

    mutating func merge(_ other: TabStructuralDirtySet) {
        dirtyTabIds.formUnion(other.dirtyTabIds)
        dirtyFolderIds.formUnion(other.dirtyFolderIds)
        dirtySpaceIds.formUnion(other.dirtySpaceIds)
        deletedTabIds.formUnion(other.deletedTabIds)
        deletedFolderIds.formUnion(other.deletedFolderIds)
        deletedSpaceIds.formUnion(other.deletedSpaceIds)
        splitGroupsDirty = splitGroupsDirty || other.splitGroupsDirty
        if let reason = other.needsFullReconcileReason {
            requestFullReconcile(reason: reason)
        }
    }
}

@MainActor
private struct TabRestoreRuntimeState {
    let spaces: [Space]
    let tabsBySpace: [UUID: [Tab]]
    let foldersBySpace: [UUID: [TabFolder]]
    let pinnedByProfile: [UUID: [ShortcutPin]]
    let pendingPinnedWithoutProfile: [ShortcutPin]
    let spacePinnedShortcuts: [UUID: [ShortcutPin]]
    let repairReasons: [String]
}

@MainActor
private struct TabRestoreRuntimeStateBuilder {
    let browserManager: BrowserManager?

    func makeState(from payload: TabRestorePayload) -> TabRestoreRuntimeState {
        var repairReasons = payload.repairReasons
        let restoredSpaces = payload.spaces.map { dto in
            let space = Space(
                id: dto.id,
                name: dto.name,
                icon: dto.icon,
                workspaceTheme: dto.workspaceTheme,
                profileId: dto.profileId
            )
            if space.icon != dto.icon {
                repairReasons.append("normalized space icon")
            }
            return space
        }

        var restoredTabsBySpace: [UUID: [Tab]] = [:]
        for space in restoredSpaces {
            restoredTabsBySpace[space.id] = []
        }
        for (spaceId, tabDTOs) in payload.regularTabsBySpace {
            restoredTabsBySpace[spaceId] = tabDTOs.map(makeRestoredTab)
        }

        var restoredFoldersBySpace: [UUID: [TabFolder]] = [:]
        for (spaceId, folderDTOs) in payload.foldersBySpace {
            restoredFoldersBySpace[spaceId] = folderDTOs.map { dto in
                let folder = TabFolder(
                    id: dto.id,
                    name: dto.name,
                    spaceId: dto.spaceId,
                    parentFolderId: dto.parentFolderId,
                    icon: dto.icon,
                    color: NSColor(hex: dto.color) ?? .controlAccentColor,
                    index: dto.index
                )
                folder.isOpen = dto.isOpen
                if folder.icon != dto.icon {
                    repairReasons.append("normalized folder icon")
                }
                return folder
            }
        }

        var restoredPinnedByProfile: [UUID: [ShortcutPin]] = [:]
        for (profileId, shortcutDTOs) in payload.pinnedShortcutsByProfile {
            restoredPinnedByProfile[profileId] = shortcutDTOs.map { dto in
                let pin = makeRestoredShortcut(dto)
                if pin.iconAsset != dto.iconAsset {
                    repairReasons.append("normalized launcher icon")
                }
                return pin
            }
        }

        let restoredPendingPinned = payload.pendingPinnedShortcuts.map { dto in
            let pin = makeRestoredShortcut(dto)
            if pin.iconAsset != dto.iconAsset {
                repairReasons.append("normalized launcher icon")
            }
            return pin
        }

        var restoredSpacePinnedShortcuts: [UUID: [ShortcutPin]] = [:]
        for (spaceId, shortcutDTOs) in payload.spacePinnedShortcutsBySpace {
            restoredSpacePinnedShortcuts[spaceId] = shortcutDTOs.map { dto in
                let pin = makeRestoredShortcut(dto)
                if pin.iconAsset != dto.iconAsset {
                    repairReasons.append("normalized launcher icon")
                }
                return pin
            }
        }

        return TabRestoreRuntimeState(
            spaces: restoredSpaces,
            tabsBySpace: restoredTabsBySpace,
            foldersBySpace: restoredFoldersBySpace,
            pinnedByProfile: restoredPinnedByProfile,
            pendingPinnedWithoutProfile: restoredPendingPinned,
            spacePinnedShortcuts: restoredSpacePinnedShortcuts,
            repairReasons: repairReasons
        )
    }

    private func makeRestoredTab(_ dto: TabRestoreTabDTO) -> Tab {
        let tab = Tab(
            id: dto.id,
            url: dto.url,
            name: dto.name,
            favicon: "globe",
            spaceId: dto.spaceId,
            index: dto.index,
            browserManager: browserManager,
            loadsCachedFaviconOnInit: false
        )
        tab.folderId = dto.folderId
        tab.profileId = dto.profileId
        tab.isPinned = false
        tab.isSpacePinned = false
        tab.canGoBack = dto.canGoBack
        tab.canGoForward = dto.canGoForward
        return tab
    }

    private func makeRestoredShortcut(_ dto: TabRestoreShortcutDTO) -> ShortcutPin {
        ShortcutPin(
            id: dto.id,
            role: dto.role,
            profileId: dto.profileId,
            executionProfileId: dto.executionProfileId,
            spaceId: dto.spaceId,
            index: dto.index,
            folderId: dto.folderId,
            launchURL: dto.launchURL,
            title: dto.title,
            iconAsset: dto.iconAsset
        )
    }
}

@MainActor
extension TabManager {
    private enum StructuralPersistencePayload: Sendable {
        case incremental(TabSnapshotRepository.StructuralDelta, TabStructuralDirtySet, Int)
        case fullReconcile(String)
    }

    public nonisolated func scheduleStructuralPersistence() {
        Task { @MainActor [weak self] in
            self?.scheduleStructuralPersistenceOnMain()
        }
    }

    /// Explicit full reconcile path for restore, repair, fallback, and termination only.
    public nonisolated func persistFullReconcileAwaitingResult(
        reason: String = "explicit full reconcile"
    ) async -> Bool {
        await MainActor.run { [weak self] in
            self?.cancelScheduledStructuralPersistence()
        }
        return await performFullReconcileNow(reason: reason)
    }

    private func scheduleStructuralPersistenceOnMain() {
        structuralPersistRequestID &+= 1
        let requestID = structuralPersistRequestID
        let debounceDelay = structuralPersistDebounceNanoseconds

        scheduledStructuralPersistTask?.cancel()
        scheduledStructuralPersistTask = Task { [weak self] in
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
            } catch {
                return
            }

            await self?.executeScheduledStructuralPersistence(requestID: requestID)
        }
    }

    private func cancelScheduledStructuralPersistence() {
        structuralPersistRequestID &+= 1
        scheduledStructuralPersistTask?.cancel()
        scheduledStructuralPersistTask = nil
    }

    private func executeScheduledStructuralPersistence(requestID: UInt64) async {
        guard structuralPersistRequestID == requestID else { return }
        scheduledStructuralPersistTask = nil
        _ = await persistIncrementalStructuralNow()
    }

    private nonisolated func persistIncrementalStructuralNow() async -> Bool {
        let signpostState = PerformanceTrace.beginInterval("TabManager.persistIncrementalStructuralNow")
        defer {
            PerformanceTrace.endInterval("TabManager.persistIncrementalStructuralNow", signpostState)
        }

        let payload: StructuralPersistencePayload? = await MainActor.run { [weak self] in
            guard let strong = self else { return nil }
            guard strong.structuralDirtySet.isEmpty == false else { return nil }

            if let reason = strong.structuralDirtySet.needsFullReconcileReason {
                strong.structuralDirtySet = TabStructuralDirtySet()
                return .fullReconcile(reason)
            }

            let pending = strong.structuralDirtySet.takePending()
            guard pending.hasIncrementalChanges else { return nil }

            strong.structuralPersistenceGeneration &+= 1
            let generation = strong.structuralPersistenceGeneration
            let delta = strong._buildStructuralDelta(from: pending)
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
                self?.structuralDirtySet.merge(consumedDirtySet)
                self?.structuralDirtySet.requestFullReconcile(
                    reason: "incremental structural persistence failed"
                )
            }
            return await performFullReconcileNow(reason: "incremental structural persistence failed")
        }
    }

    @discardableResult
    public nonisolated func flushRuntimeStatePersistenceAwaitingResult() async -> Int {
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
            strong.structuralPersistenceGeneration &+= 1
            let generation = strong.structuralPersistenceGeneration
            let snapshot = strong._buildSnapshot()
            return (snapshot, generation)
        }
        guard let (snapshot, generation) = payload else {
            return false
        }
        let didPersist = await persistence.persistFullReconcile(snapshot: snapshot, generation: generation)
        if didPersist {
            await MainActor.run { [weak self] in
                self?.structuralDirtySet = TabStructuralDirtySet()
            }
        }
        return didPersist
    }

    /// Lightweight persistence for tab selection changes only.
    /// Avoids rebuilding the full snapshot graph when only currentTabID/currentSpaceID changed.
    func persistSelection() {
        let tabID = persistableCurrentTabID()
        let spaceID = currentSpace?.id
        Task { [persistence] in
            let signpostState = PerformanceTrace.beginInterval("TabManager.persistSelection")
            defer {
                PerformanceTrace.endInterval("TabManager.persistSelection", signpostState)
            }
            await persistence.persistSelectionOnly(currentTabID: tabID, currentSpaceID: spaceID)
        }
    }

    func scheduleRuntimeStatePersistence(for tab: Tab) {
        guard shouldPersistRuntimeState(for: tab) else { return }

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

    private func shouldPersistRuntimeState(for tab: Tab) -> Bool {
        shouldPersistRegularTab(tab)
    }

    func shouldPersistRegularTab(_ tab: Tab) -> Bool {
        guard tab.isEphemeral == false else { return false }
        guard tab.isShortcutLiveInstance == false else { return false }
        guard tab.isPinned == false, tab.isSpacePinned == false else { return false }
        guard tab.spaceId != nil else { return false }
        guard ExtensionUtils.isExtensionOwnedURL(tab.url) == false else { return false }
        return true
    }

    func persistableCurrentTabID() -> UUID? {
        guard let currentTab, shouldPersistRegularTab(currentTab) else {
            return nil
        }
        return currentTab.id
    }

    func _buildSnapshot() -> TabSnapshotRepository.Snapshot {
        PerformanceTrace.withInterval("TabManager._buildSnapshot") {
            snapshotCache.makeSnapshot(for: self)
        }
    }

    func _buildStructuralDelta(
        from dirtySet: TabStructuralDirtySet
    ) -> TabSnapshotRepository.StructuralDelta {
        TabStructuralSnapshotMaterializer().makeStructuralDelta(
            from: dirtySet,
            spaces: spaces,
            pinnedByProfile: pinnedByProfile,
            spacePinnedShortcuts: spacePinnedShortcuts,
            tabsBySpace: tabsBySpace,
            foldersBySpace: foldersBySpace,
            splitGroups: splitGroups,
            currentTabId: persistableCurrentTabID(),
            currentSpaceId: currentSpace?.id,
            shouldPersistRegularTab: shouldPersistRegularTab
        )
    }

    func markSnapshotCacheDirty() {
        snapshotCache.invalidateAll()
    }

    func markSpacesSnapshotDirty() {
        snapshotCache.invalidateSpaces()
    }

    func markAllSpacesStructurallyDirty() {
        markSpacesSnapshotDirty()
        structuralDirtySet.markSpacesDirty(spaces.map(\.id))
    }

    func markSpaceStructurallyDeleted(_ spaceId: UUID) {
        structuralDirtySet.markSpacesDeleted([spaceId])
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
        structuralDirtySet.markTabsDirty((tabsBySpace[spaceId] ?? []).map(\.id))
    }

    func markFoldersSnapshotDirty(for spaceId: UUID) {
        snapshotCache.invalidateFolders(spaceId: spaceId)
    }

    func markFoldersStructurallyDirty(for spaceId: UUID) {
        markFoldersSnapshotDirty(for: spaceId)
        structuralDirtySet.markFoldersDirty((foldersBySpace[spaceId] ?? []).map(\.id))
    }

    func resetStructuralDirtySet() {
        structuralDirtySet = TabStructuralDirtySet()
    }

    func recordRegularTabsStructuralChange(previous: [Tab], current: [Tab]) {
        let previousIds = Set(previous.map(\.id))
        let currentIds = Set(current.map(\.id))
        structuralDirtySet.markTabsDeleted(previousIds.subtracting(currentIds))
        structuralDirtySet.markTabsDirty(current.map(\.id))
    }

    func recordFoldersStructuralChange(previous: [TabFolder], current: [TabFolder]) {
        let previousIds = Set(previous.map(\.id))
        let currentIds = Set(current.map(\.id))
        structuralDirtySet.markFoldersDeleted(previousIds.subtracting(currentIds))
        structuralDirtySet.markFoldersDirty(current.map(\.id))
    }

    func recordShortcutPinsStructuralChange(previous: [ShortcutPin], current: [ShortcutPin]) {
        let previousIds = Set(previous.map(\.id))
        let currentIds = Set(current.map(\.id))
        structuralDirtySet.markTabsDeleted(previousIds.subtracting(currentIds))
        structuralDirtySet.markTabsDirty(current.map(\.id))
    }

    func hasLiveRuntimeContent(in space: Space) -> Bool {
        let spaceId = space.id

        if !(tabsBySpace[spaceId] ?? []).isEmpty { return true }
        if !(spacePinnedShortcuts[spaceId] ?? []).isEmpty { return true }
        if !(foldersBySpace[spaceId] ?? []).isEmpty { return true }

        return transientShortcutTabsByWindow.values
            .flatMap(\.values)
            .contains { $0.spaceId == spaceId }
    }

    func reconcileProfileRuntimeStates(activeSpaceId: UUID?) {
        for space in spaces {
            let hasRuntimeContent = hasLiveRuntimeContent(in: space)

            if space.id == activeSpaceId {
                space.profileRuntimeState = hasRuntimeContent ? .active : .dormant
            } else {
                space.profileRuntimeState = hasRuntimeContent ? .loadedInactive : .dormant
            }
        }
    }

    func loadFromStore() {
        startupRestoreTask?.cancel()
        startupRestoreTask = Task { [weak self] in
            _ = await self?.loadFromStoreAwaitingResult()
        }
    }

    @discardableResult
    func loadFromStoreAwaitingResult() async -> Bool {
        let signpostState = PerformanceTrace.beginInterval("TabManager.loadFromStore")
        defer {
            PerformanceTrace.endInterval("TabManager.loadFromStore", signpostState)
        }

        markInitialDataLoadStarted()
        defer {
            markInitialDataLoadFinished()
            startupRestoreTask = nil
            NotificationCenter.default.post(name: .tabManagerDidLoadInitialData, object: nil)
        }

        do {
            let defaultProfileId = runtimeContext?.defaultProfileId
            if defaultProfileId == nil {
                RuntimeDiagnostics.debug(
                    "No profiles available to assign to spaces during load; reconciliation deferred.",
                    category: "TabManager"
                )
            }

            let loader = TabRestoreLoader(container: context.container)
            let payload = try await loader.load(defaultProfileId: defaultProfileId)
            if Task.isCancelled { return false }

            let applyResult = applyRestorePayload(payload)
            enqueueRestoreRepairIfNeeded(applyResult)
            return true
        } catch {
            RuntimeDiagnostics.debug("SwiftData load error: \(String(describing: error))", category: "TabManager")
            return false
        }
    }

    private struct RestoreApplyResult {
        let snapshot: TabSnapshotRepository.Snapshot?
        let reasons: [String]
    }

    private func applyRestorePayload(_ payload: TabRestorePayload) -> RestoreApplyResult {
        let signpostState = PerformanceTrace.beginInterval("TabManager.restoreApplyMainActor")
        defer {
            PerformanceTrace.endInterval("TabManager.restoreApplyMainActor", signpostState)
        }

        RuntimeDiagnostics.debug(
            "Loading tabs from store: total=\(payload.totalTabCount), pinned=\(payload.pinnedCount), spacePinned=\(payload.spacePinnedCount), regular=\(payload.regularCount)",
            category: "TabManager"
        )

        let restoredState = TabRestoreRuntimeStateBuilder(browserManager: browserManager)
            .makeState(from: payload)

        spaces = restoredState.spaces
        tabsBySpace = restoredState.tabsBySpace
        foldersBySpace = restoredState.foldersBySpace
        pinnedByProfile = restoredState.pinnedByProfile
        pendingPinnedWithoutProfile = restoredState.pendingPinnedWithoutProfile
        spacePinnedShortcuts = restoredState.spacePinnedShortcuts
        splitGroups = sanitizedRepairedSplitGroups(payload.splitGroups)

        for tab in restoredState.tabsBySpace.values.flatMap(\.self) {
            tab.browserManager = browserManager
        }

        currentSpace = payload.currentSpaceId.flatMap { currentSpaceId in
            restoredState.spaces.first(where: { $0.id == currentSpaceId })
        } ?? restoredState.spaces.first

        let selectionTabs = currentSpace.flatMap { restoredState.tabsBySpace[$0.id] } ?? []
        if let selectedTabId = payload.currentTabId,
           let match = selectionTabs.first(where: { $0.id == selectedTabId }) {
            currentTab = match
        } else {
            currentTab = selectionTabs.first
        }

        rebuildTabLookupForRestore()
        lazyRestoreCoordinator.reset(
            restoredTabIDs: Set(restoredState.tabsBySpace.values.flatMap { $0.map(\.id) })
        )
        markSnapshotCacheDirty()
        resetStructuralDirtySet()
        structuralPersistRequestID &+= 1
        scheduledStructuralPersistTask?.cancel()
        scheduledStructuralPersistTask = nil
        requestStructuralPublish()

        RuntimeDiagnostics.debug(
            "Current Space: \(currentSpace?.name ?? "None"), Tab: \(currentTab?.name ?? "None")",
            category: "TabManager"
        )

        if let currentSpace {
            runtimeContext?.syncWorkspaceThemeAcrossWindows(for: currentSpace, animate: false)
        }

        let uniqueRepairReasons = Array(Set(restoredState.repairReasons)).sorted()
        guard uniqueRepairReasons.isEmpty == false else {
            return RestoreApplyResult(snapshot: nil, reasons: [])
        }

        let snapshot = uniqueRepairReasons == payload.repairReasons
            ? payload.snapshot
            : _buildSnapshot()
        return RestoreApplyResult(snapshot: snapshot, reasons: uniqueRepairReasons)
    }

    private func enqueueRestoreRepairIfNeeded(_ result: RestoreApplyResult) {
        guard let snapshot = result.snapshot else {
            return
        }

        structuralPersistenceGeneration &+= 1
        let generation = structuralPersistenceGeneration
        let persistence = self.persistence
        let reasonSummary = result.reasons.joined(separator: ", ")
        Task {
            let signpostState = PerformanceTrace.beginInterval("TabManager.restoreRepairFullReconcile")
            defer {
                PerformanceTrace.endInterval("TabManager.restoreRepairFullReconcile", signpostState)
            }
            RuntimeDiagnostics.debug(
                "Persisting restore repair via full reconcile: \(reasonSummary)",
                category: "TabManager"
            )
            _ = await persistence.persistFullReconcile(snapshot: snapshot, generation: generation)
        }
    }

}
