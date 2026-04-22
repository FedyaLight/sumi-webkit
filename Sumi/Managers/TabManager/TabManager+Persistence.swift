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
        PerformanceTrace.emitEvent("TabManager.runtimeState.enqueue")
        runtimeStateCoalescer.enqueue(payload)
    }

    func cancelRuntimeStatePersistence(for tabId: UUID) {
        runtimeStateCoalescer.cancel(tabID: tabId)
    }

    private func shouldPersistRuntimeState(for tab: Tab) -> Bool {
        guard tab.isShortcutLiveInstance == false else { return false }
        guard tab.isPinned == false, tab.isSpacePinned == false else { return false }
        return tab.spaceId != nil
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
        SidebarUITestDragMarker.recordEvent(
            "startupLoadBegin",
            dragItemID: nil,
            ownerDescription: "TabManager.loadFromStore",
            details: "storeLoadStarted=true"
        )
        defer {
            markInitialDataLoadFinished()
            startupRestoreTask = nil
            NotificationCenter.default.post(name: .tabManagerDidLoadInitialData, object: nil)
        }

        do {
            let defaultProfileId = browserManager?.currentProfile?.id
                ?? browserManager?.profileManager.profiles.first?.id
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
            SidebarUITestDragMarker.recordEvent(
                "startupLoadFailed",
                dragItemID: nil,
                ownerDescription: "TabManager.loadFromStore",
                details: "error=\(String(describing: error))"
            )
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

        var mainRepairReasons = payload.repairReasons
        let restoredSpaces = payload.spaces.map { dto in
            let space = Space(
                id: dto.id,
                name: dto.name,
                icon: dto.icon,
                workspaceTheme: dto.workspaceTheme,
                profileId: dto.profileId
            )
            if space.icon != dto.icon {
                mainRepairReasons.append("normalized space icon")
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
                    icon: dto.icon,
                    color: NSColor(hex: dto.color) ?? .controlAccentColor,
                    index: dto.index
                )
                folder.isOpen = dto.isOpen
                if folder.icon != dto.icon {
                    mainRepairReasons.append("normalized folder icon")
                }
                return folder
            }
        }

        var restoredPinnedByProfile: [UUID: [ShortcutPin]] = [:]
        for (profileId, shortcutDTOs) in payload.pinnedShortcutsByProfile {
            restoredPinnedByProfile[profileId] = shortcutDTOs.map { dto in
                let pin = makeRestoredShortcut(dto)
                if pin.iconAsset != dto.iconAsset {
                    mainRepairReasons.append("normalized launcher icon")
                }
                return pin
            }
        }

        let restoredPendingPinned = payload.pendingPinnedShortcuts.map { dto in
            let pin = makeRestoredShortcut(dto)
            if pin.iconAsset != dto.iconAsset {
                mainRepairReasons.append("normalized launcher icon")
            }
            return pin
        }

        var restoredSpacePinnedShortcuts: [UUID: [ShortcutPin]] = [:]
        for (spaceId, shortcutDTOs) in payload.spacePinnedShortcutsBySpace {
            restoredSpacePinnedShortcuts[spaceId] = shortcutDTOs.map { dto in
                let pin = makeRestoredShortcut(dto)
                if pin.iconAsset != dto.iconAsset {
                    mainRepairReasons.append("normalized launcher icon")
                }
                return pin
            }
        }

        spaces = restoredSpaces
        tabsBySpace = restoredTabsBySpace
        foldersBySpace = restoredFoldersBySpace
        pinnedByProfile = restoredPinnedByProfile
        pendingPinnedWithoutProfile = restoredPendingPinned
        spacePinnedShortcuts = restoredSpacePinnedShortcuts

        for tab in restoredTabsBySpace.values.flatMap(\.self) {
            tab.browserManager = browserManager
        }

        currentSpace = payload.currentSpaceId.flatMap { currentSpaceId in
            restoredSpaces.first(where: { $0.id == currentSpaceId })
        } ?? restoredSpaces.first

        let selectionTabs = currentSpace.flatMap { restoredTabsBySpace[$0.id] } ?? []
        if let selectedTabId = payload.currentTabId,
           let match = selectionTabs.first(where: { $0.id == selectedTabId }) {
            currentTab = match
        } else {
            currentTab = selectionTabs.first
        }

        rebuildTabLookupForRestore()
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
        SidebarUITestDragMarker.recordEvent(
            "startupLoadComplete",
            dragItemID: nil,
            ownerDescription: "TabManager.loadFromStore",
            details: "spaces=\(spaces.count) currentSpace=\(currentSpace?.id.uuidString ?? "nil") currentTab=\(currentTab?.id.uuidString ?? "nil") currentProfile=\(browserManager?.currentProfile?.id.uuidString ?? "nil") pinnedProfiles=\(pinnedByProfile.count) spacePinnedGroups=\(spacePinnedShortcuts.count)"
        )

        if let browserManager, let currentSpace {
            browserManager.syncWorkspaceThemeAcrossWindows(for: currentSpace, animate: false)
        }

        let uniqueRepairReasons = Array(Set(mainRepairReasons)).sorted()
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

    private func makeRestoredTab(_ dto: TabRestoreTabDTO) -> Tab {
        let faviconName = SumiSurface.isSettingsSurfaceURL(dto.url)
            ? SumiSurface.settingsTabFaviconSystemImageName
            : "globe"
        let tab = Tab(
            id: dto.id,
            url: dto.url,
            name: dto.name,
            favicon: faviconName,
            spaceId: dto.spaceId,
            index: dto.index,
            browserManager: browserManager,
            skipFaviconFetch: true
        )
        tab.folderId = dto.folderId
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
            spaceId: dto.spaceId,
            index: dto.index,
            folderId: dto.folderId,
            launchURL: dto.launchURL,
            title: dto.title,
            faviconCacheKey: dto.faviconCacheKey,
            iconAsset: dto.iconAsset
        )
    }
}
