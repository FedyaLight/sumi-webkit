import AppKit
import Foundation
import SwiftData

@MainActor
struct TabManagerSnapshotCache {
    private typealias SnapshotSpace = TabSnapshotRepository.SnapshotSpace
    private typealias SnapshotTab = TabSnapshotRepository.SnapshotTab
    private typealias SnapshotFolder = TabSnapshotRepository.SnapshotFolder

    private var spaceSnapshots: [SnapshotSpace] = []
    private var pinnedTabsByProfile: [UUID: [SnapshotTab]] = [:]
    private var spacePinnedTabsBySpace: [UUID: [SnapshotTab]] = [:]
    private var regularTabsBySpace: [UUID: [SnapshotTab]] = [:]
    private var folderSnapshotsBySpace: [UUID: [SnapshotFolder]] = [:]

    private var spacesDirty = true
    private var dirtyPinnedProfileIds: Set<UUID> = []
    private var dirtySpacePinnedSpaceIds: Set<UUID> = []
    private var dirtyRegularTabSpaceIds: Set<UUID> = []
    private var dirtyFolderSpaceIds: Set<UUID> = []

    mutating func invalidateAll() {
        spacesDirty = true
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
            spaceSnapshots = orderedSpaces.enumerated().map { index, space in
                SnapshotSpace(
                    id: space.id,
                    name: space.name,
                    icon: space.icon,
                    index: index,
                    gradientData: space.gradient.encoded,
                    workspaceThemeData: space.workspaceTheme.encoded,
                    activeTabId: space.activeTabId,
                    profileId: space.profileId
                )
            }
            spacesDirty = false
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

        for profileId in tabManager.pinnedByProfile.keys.sorted(by: uuidLessThan) {
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

        let state = TabSnapshotRepository.SnapshotState(
            currentTabID: tabManager.currentTab?.id,
            currentSpaceID: tabManager.currentSpace?.id
        )

        return TabSnapshotRepository.Snapshot(
            spaces: spaceSnapshots,
            tabs: tabSnapshots,
            folders: folderSnapshots,
            state: state
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
            let orderedPins = Array(tabManager.pinnedByProfile[profileId] ?? []).sorted { $0.index < $1.index }
            pinnedTabsByProfile[profileId] = orderedPins.enumerated().map { index, pin in
                SnapshotTab(
                    id: pin.id,
                    urlString: pin.launchURL.absoluteString,
                    name: pin.title,
                    index: index,
                    spaceId: nil,
                    isPinned: true,
                    isSpacePinned: false,
                    profileId: profileId,
                    folderId: nil,
                    iconAsset: pin.iconAsset,
                    currentURLString: pin.launchURL.absoluteString,
                    canGoBack: false,
                    canGoForward: false
                )
            }
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
            let shortcutPins = Array(tabManager.spacePinnedShortcuts[spaceId] ?? []).sorted { $0.index < $1.index }
            spacePinnedTabsBySpace[spaceId] = shortcutPins.enumerated().map { index, pin in
                SnapshotTab(
                    id: pin.id,
                    urlString: pin.launchURL.absoluteString,
                    name: pin.title,
                    index: index,
                    spaceId: spaceId,
                    isPinned: false,
                    isSpacePinned: true,
                    profileId: nil,
                    folderId: pin.folderId,
                    iconAsset: pin.iconAsset,
                    currentURLString: pin.launchURL.absoluteString,
                    canGoBack: false,
                    canGoForward: false
                )
            }
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
            regularTabsBySpace[spaceId] = regularTabs.enumerated().map { index, tab in
                SnapshotTab(
                    id: tab.id,
                    urlString: tab.url.absoluteString,
                    name: tab.name,
                    index: index,
                    spaceId: spaceId,
                    isPinned: false,
                    isSpacePinned: false,
                    profileId: nil,
                    folderId: tab.folderId,
                    iconAsset: nil,
                    currentURLString: tab.url.absoluteString,
                    canGoBack: tab.canGoBack,
                    canGoForward: tab.canGoForward
                )
            }
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
            let orderedFolders = (tabManager.foldersBySpace[spaceId] ?? []).sorted { $0.index < $1.index }
            folderSnapshotsBySpace[spaceId] = orderedFolders.enumerated().map { index, folder in
                SnapshotFolder(
                    id: folder.id,
                    name: folder.name,
                    icon: SumiZenFolderIconCatalog.normalizedFolderIconValue(folder.icon),
                    color: folder.color.toHexString() ?? "#000000",
                    spaceId: spaceId,
                    isOpen: folder.isOpen,
                    index: index
                )
            }
        }
        dirtyFolderSpaceIds.removeAll(keepingCapacity: true)
    }

    private func uuidLessThan(_ lhs: UUID, _ rhs: UUID) -> Bool {
        lhs.uuidString < rhs.uuidString
    }
}

struct TabStructuralDirtySet: Sendable {
    var dirtyTabIds: Set<UUID> = []
    var dirtyFolderIds: Set<UUID> = []
    var dirtySpaceIds: Set<UUID> = []
    var deletedTabIds: Set<UUID> = []
    var deletedFolderIds: Set<UUID> = []
    var deletedSpaceIds: Set<UUID> = []
    var needsFullReconcileReason: String?

    var isEmpty: Bool {
        dirtyTabIds.isEmpty
            && dirtyFolderIds.isEmpty
            && dirtySpaceIds.isEmpty
            && deletedTabIds.isEmpty
            && deletedFolderIds.isEmpty
            && deletedSpaceIds.isEmpty
            && needsFullReconcileReason == nil
    }

    var hasIncrementalChanges: Bool {
        dirtyTabIds.isEmpty == false
            || dirtyFolderIds.isEmpty == false
            || dirtySpaceIds.isEmpty == false
            || deletedTabIds.isEmpty == false
            || deletedFolderIds.isEmpty == false
            || deletedSpaceIds.isEmpty == false
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
        if let reason = other.needsFullReconcileReason {
            requestFullReconcile(reason: reason)
        }
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

    public nonisolated func flushStructuralPersistenceAwaitingResult() async -> Bool {
        await MainActor.run { [weak self] in
            self?.cancelScheduledStructuralPersistence()
        }
        return await persistIncrementalStructuralNow()
    }

    /// Explicit full reconcile path for restore, repair, migration, and incremental fallback only.
    public nonisolated func persistFullReconcile(reason: String = "explicit full reconcile") {
        Task { [weak self] in
            _ = await self?.persistFullReconcileAwaitingResult(reason: reason)
        }
    }

    public nonisolated func persistFullReconcileAwaitingResult(
        reason: String = "explicit full reconcile"
    ) async -> Bool {
        await MainActor.run { [weak self] in
            self?.cancelScheduledStructuralPersistence()
        }
        return await persistFullSnapshotNow(reason: reason)
    }

    /// Compatibility wrapper. Do not use for normal runtime mutations; call
    /// `scheduleStructuralPersistence()` for the incremental hot path instead.
    public nonisolated func persistSnapshot() {
        persistFullReconcile(reason: "legacy persistSnapshot() call")
    }

    // Returns true if the full atomic path succeeded; false if fallback was used or stale.
    public nonisolated func persistSnapshotAwaitingResult() async -> Bool {
        await persistFullReconcileAwaitingResult(reason: "legacy persistSnapshotAwaitingResult() call")
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
            return await persistFullSnapshotNow(reason: reason)
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
            return await persistFullSnapshotNow(reason: "incremental structural persistence failed")
        }
    }

    private nonisolated func persistFullSnapshotNow(reason _: String) async -> Bool {
        let signpostState = PerformanceTrace.beginInterval("TabManager.persistFullSnapshotNow")
        defer {
            PerformanceTrace.endInterval("TabManager.persistFullSnapshotNow", signpostState)
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
        let tabID = currentTab?.id
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

        let tabID = tab.id
        if let spaceId = tab.spaceId {
            markRegularTabsSnapshotDirty(for: spaceId)
        }
        let debounceDelay = runtimeStatePersistDebounceNanoseconds
        pendingRuntimeStatePersistTasks[tabID]?.cancel()
        pendingRuntimeStatePersistTasks[tabID] = Task { [weak self, weak tab] in
            do {
                try await Task.sleep(nanoseconds: debounceDelay)
            } catch {
                return
            }

            guard let self, let tab else { return }
            self.pendingRuntimeStatePersistTasks.removeValue(forKey: tabID)
            await self.persistRuntimeStateNow(for: tab)
        }
    }

    func cancelRuntimeStatePersistence(for tabId: UUID) {
        pendingRuntimeStatePersistTasks[tabId]?.cancel()
        pendingRuntimeStatePersistTasks.removeValue(forKey: tabId)
    }

    private func shouldPersistRuntimeState(for tab: Tab) -> Bool {
        guard tab.isShortcutLiveInstance == false else { return false }
        guard tab.isPinned == false, tab.isSpacePinned == false else { return false }
        return tab.spaceId != nil
    }

    private nonisolated func persistRuntimeStateNow(for tab: Tab) async {
        let signpostState = PerformanceTrace.beginInterval("TabManager.persistRuntimeStateNow")
        defer {
            PerformanceTrace.endInterval("TabManager.persistRuntimeStateNow", signpostState)
        }

        let payload: TabSnapshotRepository.RuntimeTabState? = await MainActor.run {
            guard self.shouldPersistRuntimeState(for: tab) else { return nil }
            return TabSnapshotRepository.RuntimeTabState(
                id: tab.id,
                urlString: tab.url.absoluteString,
                currentURLString: tab.url.absoluteString,
                name: tab.name,
                canGoBack: tab.canGoBack,
                canGoForward: tab.canGoForward
            )
        }
        guard let payload else { return }
        await persistence.persistRuntimeState(payload)
    }

    func _buildSnapshot() -> TabSnapshotRepository.Snapshot {
        PerformanceTrace.withInterval("TabManager._buildSnapshot") {
            snapshotCache.makeSnapshot(for: self)
        }
    }

    func _buildStructuralDelta(
        from dirtySet: TabStructuralDirtySet
    ) -> TabSnapshotRepository.StructuralDelta {
        TabSnapshotRepository.StructuralDelta(
            spaces: makeDirtySpaceSnapshots(for: dirtySet.dirtySpaceIds),
            tabs: makeDirtyTabSnapshots(for: dirtySet.dirtyTabIds),
            folders: makeDirtyFolderSnapshots(for: dirtySet.dirtyFolderIds),
            deletedSpaceIds: dirtySet.deletedSpaceIds,
            deletedTabIds: dirtySet.deletedTabIds,
            deletedFolderIds: dirtySet.deletedFolderIds,
            state: TabSnapshotRepository.SnapshotState(
                currentTabID: currentTab?.id,
                currentSpaceID: currentSpace?.id
            )
        )
    }

    private func makeDirtySpaceSnapshots(for ids: Set<UUID>) -> [TabSnapshotRepository.SnapshotSpace] {
        guard ids.isEmpty == false else { return [] }
        return spaces.enumerated().compactMap { index, space in
            guard ids.contains(space.id) else { return nil }
            return TabSnapshotRepository.SnapshotSpace(
                id: space.id,
                name: space.name,
                icon: space.icon,
                index: index,
                gradientData: space.gradient.encoded,
                workspaceThemeData: space.workspaceTheme.encoded,
                activeTabId: space.activeTabId,
                profileId: space.profileId
            )
        }
    }

    private func makeDirtyTabSnapshots(for ids: Set<UUID>) -> [TabSnapshotRepository.SnapshotTab] {
        guard ids.isEmpty == false else { return [] }
        var snapshots: [TabSnapshotRepository.SnapshotTab] = []

        for profileId in pinnedByProfile.keys.sorted(by: { $0.uuidString < $1.uuidString }) {
            let orderedPins = Array(pinnedByProfile[profileId] ?? []).sorted { $0.index < $1.index }
            for (index, pin) in orderedPins.enumerated() where ids.contains(pin.id) {
                snapshots.append(
                    TabSnapshotRepository.SnapshotTab(
                        id: pin.id,
                        urlString: pin.launchURL.absoluteString,
                        name: pin.title,
                        index: index,
                        spaceId: nil,
                        isPinned: true,
                        isSpacePinned: false,
                        profileId: profileId,
                        folderId: nil,
                        iconAsset: pin.iconAsset,
                        currentURLString: pin.launchURL.absoluteString,
                        canGoBack: false,
                        canGoForward: false
                    )
                )
            }
        }

        for space in spaces {
            let shortcutPins = Array(spacePinnedShortcuts[space.id] ?? []).sorted { $0.index < $1.index }
            for (index, pin) in shortcutPins.enumerated() where ids.contains(pin.id) {
                snapshots.append(
                    TabSnapshotRepository.SnapshotTab(
                        id: pin.id,
                        urlString: pin.launchURL.absoluteString,
                        name: pin.title,
                        index: index,
                        spaceId: space.id,
                        isPinned: false,
                        isSpacePinned: true,
                        profileId: nil,
                        folderId: pin.folderId,
                        iconAsset: pin.iconAsset,
                        currentURLString: pin.launchURL.absoluteString,
                        canGoBack: false,
                        canGoForward: false
                    )
                )
            }

            let regularTabs = Array(tabsBySpace[space.id] ?? [])
            for (index, tab) in regularTabs.enumerated() where ids.contains(tab.id) {
                snapshots.append(
                    TabSnapshotRepository.SnapshotTab(
                        id: tab.id,
                        urlString: tab.url.absoluteString,
                        name: tab.name,
                        index: index,
                        spaceId: space.id,
                        isPinned: false,
                        isSpacePinned: false,
                        profileId: nil,
                        folderId: tab.folderId,
                        iconAsset: nil,
                        currentURLString: tab.url.absoluteString,
                        canGoBack: tab.canGoBack,
                        canGoForward: tab.canGoForward
                    )
                )
            }
        }

        return snapshots
    }

    private func makeDirtyFolderSnapshots(for ids: Set<UUID>) -> [TabSnapshotRepository.SnapshotFolder] {
        guard ids.isEmpty == false else { return [] }
        var snapshots: [TabSnapshotRepository.SnapshotFolder] = []
        for space in spaces {
            let orderedFolders = (foldersBySpace[space.id] ?? []).sorted { $0.index < $1.index }
            for (index, folder) in orderedFolders.enumerated() where ids.contains(folder.id) {
                snapshots.append(
                    TabSnapshotRepository.SnapshotFolder(
                        id: folder.id,
                        name: folder.name,
                        icon: SumiZenFolderIconCatalog.normalizedFolderIconValue(folder.icon),
                        color: folder.color.toHexString() ?? "#000000",
                        spaceId: space.id,
                        isOpen: folder.isOpen,
                        index: index
                    )
                )
            }
        }
        return snapshots
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

    func requestFullStructuralReconcile(reason: String) {
        structuralDirtySet.requestFullReconcile(reason: reason)
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
        let signpostState = PerformanceTrace.beginInterval("TabManager.loadFromStore")
        defer {
            PerformanceTrace.endInterval("TabManager.loadFromStore", signpostState)
        }

        markInitialDataLoadStarted()
        SidebarUITestDragMarker.recordEvent(
            "startupLoadBegin",
            dragItemID: nil,
            ownerDescription: "TabManager.loadFromStore",
            details: "storeLoadStarted=true"
        )
        defer {
            markInitialDataLoadFinished()
            NotificationCenter.default.post(name: .tabManagerDidLoadInitialData, object: nil)
        }

        do {
            let defaultRestoreURL = URL(string: "about:blank")!
            var needsSnapshotPersistence = false

            let spaceEntities = try context.fetch(
                FetchDescriptor<SpaceEntity>()
            )
            var didNormalizeSpaceIcons = false
            for entity in spaceEntities {
                let normalized = SumiPersistentGlyph.normalizedSpaceIconValue(entity.icon)
                if normalized != entity.icon {
                    entity.icon = normalized
                    didNormalizeSpaceIcons = true
                }
            }
            if didNormalizeSpaceIcons {
                try context.save()
            }
            let sortedSpaces = spaceEntities.sorted { $0.index < $1.index }
            self.spaces = sortedSpaces.map { entity in
                let workspaceTheme: WorkspaceTheme
                workspaceTheme = WorkspaceTheme.decode(entity.workspaceThemeData ?? Data())
                    ?? WorkspaceTheme(
                        gradient: SpaceGradient.decode(entity.gradientData)
                    )
                return Space(
                    id: entity.id,
                    name: entity.name,
                    icon: entity.icon,
                    workspaceTheme: workspaceTheme,
                    profileId: entity.profileId
                )
            }
            for sp in spaces {
                setTabs([], for: sp.id)
            }

            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let dp = defaultProfileId {
                var didAssignProfiles = false
                for space in spaces where space.profileId == nil {
                    space.profileId = dp
                    didAssignProfiles = true
                }
                if didAssignProfiles {
                    needsSnapshotPersistence = true
                }
            } else {
                RuntimeDiagnostics.debug("No profiles available to assign to spaces during load; reconciliation deferred.", category: "TabManager")
            }

            let tabEntities = try context.fetch(FetchDescriptor<TabEntity>())
            let sortedTabs = tabEntities.sorted { a, b in
                if a.isPinned != b.isPinned { return a.isPinned && !b.isPinned }
                if a.isSpacePinned != b.isSpacePinned { return a.isSpacePinned && !b.isPinned }
                if a.spaceId != b.spaceId {
                    return (a.spaceId?.uuidString ?? "")
                        < (b.spaceId?.uuidString ?? "")
                }
                return a.index < b.index
            }

            let globalPinned = sortedTabs.filter { $0.isPinned }
            let spacePinned = sortedTabs.filter { $0.isSpacePinned && !$0.isPinned }
            let normals = sortedTabs.filter { !$0.isPinned && !$0.isSpacePinned && $0.folderId == nil }

            RuntimeDiagnostics.debug(
                "Loading tabs from store: total=\(sortedTabs.count), pinned=\(globalPinned.count), spacePinned=\(spacePinned.count), regular=\(normals.count)",
                category: "TabManager"
            )

            var pinnedMap: [UUID: [ShortcutPin]] = [:]
            let fallbackProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            var didAssignDefaultProfile = false
            var pendingPins: [ShortcutPin] = []
            for entity in globalPinned {
                let resolvedURL = URL(string: entity.urlString) ?? defaultRestoreURL
                let pin = ShortcutPin(
                    id: entity.id,
                    role: .essential,
                    profileId: entity.profileId ?? fallbackProfileId,
                    spaceId: nil,
                    index: entity.index,
                    folderId: nil,
                    launchURL: resolvedURL,
                    title: entity.name,
                    faviconCacheKey: ShortcutPin.makeFaviconCacheKey(for: resolvedURL),
                    iconAsset: entity.iconAsset
                )
                if let stored = entity.profileId {
                    var pins = pinnedMap[stored] ?? []
                    pins.append(pin)
                    pinnedMap[stored] = pins
                } else if let fallbackProfileId {
                    didAssignDefaultProfile = true
                    var pins = pinnedMap[fallbackProfileId] ?? []
                    pins.append(pin)
                    pinnedMap[fallbackProfileId] = pins
                } else {
                    pendingPins.append(pin)
                }
            }
            pinnedByProfile = pinnedMap
            pendingPinnedWithoutProfile = pendingPins

            for entity in spacePinned {
                if let spaceId = entity.spaceId {
                    let resolvedURL = URL(string: entity.urlString) ?? defaultRestoreURL
                    let pin = ShortcutPin(
                        id: entity.id,
                        role: .spacePinned,
                        profileId: nil,
                        spaceId: spaceId,
                        index: entity.index,
                        folderId: entity.folderId,
                        launchURL: resolvedURL,
                        title: entity.name,
                        faviconCacheKey: ShortcutPin.makeFaviconCacheKey(for: resolvedURL),
                        iconAsset: entity.iconAsset
                    )
                    var pins = spacePinnedShortcuts[spaceId] ?? []
                    pins.append(pin)
                    setSpacePinnedShortcuts(pins, for: spaceId)
                } else {
                    RuntimeDiagnostics.debug("Skipping malformed space-pinned launcher '\(entity.name)' without a spaceId during load.", category: "TabManager")
                }
            }

            for entity in normals {
                let runtimeTab = toRuntime(entity, defaultRestoreURL: defaultRestoreURL)
                if let spaceId = entity.spaceId {
                    var tabs = tabsBySpace[spaceId] ?? []
                    tabs.append(runtimeTab)
                    setTabs(tabs, for: spaceId)
                }
            }

            let folderEntities = try context.fetch(FetchDescriptor<FolderEntity>())
            var didNormalizeFolderIcons = false
            for entity in folderEntities {
                let normalizedIcon = SumiZenFolderIconCatalog.normalizedFolderIconValue(entity.icon)
                if normalizedIcon != entity.icon {
                    entity.icon = normalizedIcon
                    didNormalizeFolderIcons = true
                }
                let folder = TabFolder(
                    id: entity.id,
                    name: entity.name,
                    spaceId: entity.spaceId,
                    icon: normalizedIcon,
                    color: NSColor(hex: entity.color) ?? .controlAccentColor
                )
                folder.isOpen = entity.isOpen
                var folders = foldersBySpace[entity.spaceId] ?? []
                folders.append(folder)
                setFolders(folders, for: entity.spaceId)
            }

            for tab in allTabsAllSpaces() {
                tab.browserManager = browserManager
            }

            let states = try context.fetch(FetchDescriptor<TabsStateEntity>())
            let state = states.first
            if spaces.isEmpty {
                let personalSpace = Space(name: "Personal", icon: "person.crop.circle", workspaceTheme: .default)
                spaces.append(personalSpace)
                setTabs([], for: personalSpace.id)
                currentSpace = personalSpace
                needsSnapshotPersistence = true
            } else if let stateSpaceId = state?.currentSpaceID,
                      let match = spaces.first(where: { $0.id == stateSpaceId }) {
                currentSpace = match
            } else {
                currentSpace = spaces.first
            }

            let selectionTabs = currentSpace.flatMap { tabsBySpace[$0.id] } ?? []
            if let selectedTabId = state?.currentTabID,
               let match = selectionTabs.first(where: { $0.id == selectedTabId }) {
                currentTab = match
            } else {
                currentTab = selectionTabs.first
            }

            RuntimeDiagnostics.debug(
                "Current Space: \(currentSpace?.name ?? "None"), Tab: \(currentTab?.name ?? "None")",
                category: "TabManager"
            )
            SidebarUITestDragMarker.recordEvent(
                "startupLoadComplete",
                dragItemID: nil,
                ownerDescription: "TabManager.loadFromStore",
                details: "spaces=\(spaces.count) currentSpace=\(currentSpace?.id.uuidString ?? "nil") currentTab=\(currentTab?.id.uuidString ?? "nil") currentProfile=\(browserManager?.currentProfile?.id.uuidString ?? "nil") pinnedProfiles=\(pinnedByProfile.count) spacePinnedGroups=\(spacePinnedShortcuts.count)"
            )

            if let browserManager, let currentSpace {
                browserManager.syncWorkspaceThemeAcrossWindows(for: currentSpace, animate: false)
            }
            markSnapshotCacheDirty()
            if didAssignDefaultProfile || didNormalizeFolderIcons || didNormalizeSpaceIcons {
                needsSnapshotPersistence = true
            }
            if needsSnapshotPersistence {
                persistFullReconcile(reason: "restore normalization")
            } else {
                resetStructuralDirtySet()
            }
        } catch {
            RuntimeDiagnostics.debug("SwiftData load error: \(String(describing: error))", category: "TabManager")
            SidebarUITestDragMarker.recordEvent(
                "startupLoadFailed",
                dragItemID: nil,
                ownerDescription: "TabManager.loadFromStore",
                details: "error=\(String(describing: error))"
            )
        }
    }

    private func toRuntime(_ entity: TabEntity, defaultRestoreURL: URL) -> Tab {
        let urlString = entity.currentURLString ?? entity.urlString
        let url = URL(string: urlString) ?? URL(string: entity.urlString) ?? defaultRestoreURL
        let faviconName = SumiSurface.isSettingsSurfaceURL(url)
            ? SumiSurface.settingsTabFaviconSystemImageName
            : "globe"
        let tab = Tab(
            id: entity.id,
            url: url,
            name: entity.name,
            favicon: faviconName,
            spaceId: entity.spaceId,
            index: entity.index,
            browserManager: browserManager,
            skipFaviconFetch: true
        )
        tab.folderId = entity.folderId
        tab.isPinned = entity.isPinned
        tab.isSpacePinned = entity.isSpacePinned
        tab.canGoBack = entity.canGoBack
        tab.canGoForward = entity.canGoForward
        return tab
    }
}
