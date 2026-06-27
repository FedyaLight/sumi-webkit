import AppKit
import Combine
import Observation
import SwiftData
import WebKit

@MainActor
class TabManager: ObservableObject {
    private static let faviconPresentationRefreshDebounceNanoseconds: UInt64 = 250_000_000

    enum TabManagerError: LocalizedError {
        case spaceNotFound(UUID)

        var errorDescription: String? {
            switch self {
            case .spaceNotFound(let id):
                return "Space with id \(id.uuidString) was not found."
            }
        }
    }
    weak var browserManager: BrowserManager?
    weak var sumiSettings: SumiSettingsService?
    let context: ModelContext
    let persistence: TabSnapshotRepository
    let runtimeStateCoalescer: RuntimeStateCoalescer

    lazy var runtimeStore = DefaultTabRuntimeStore(tabManager: self)
    lazy var folderService = TabFolderService(tabManager: self)
    lazy var regularTabCollectionOwner = RegularTabCollectionOwner(tabManager: self)
    lazy var regularTabDragService = SidebarRegularTabDragService(tabManager: self)
    lazy var lazyRestoreCoordinator = TabLazyRestoreCoordinator(tabManager: self)

    // Spaces
    @Published var spaces: [Space] = []
    @Published var currentSpace: Space?

    // Normal tabs per space
    @Published var tabsBySpace: [UUID: [Tab]] = [:]

    // Structural split groups, restored and persisted with the tab model.
    @Published var splitGroups: [SplitGroup] = [] {
        didSet {
            splitGroupIndexStore.rebuild(from: splitGroups)
        }
    }
    var splitGroupIndexStore = SplitGroupIndexStore()

    // Folders per space
    @Published var foldersBySpace: [UUID: [TabFolder]] = [:]

    // Global pinned launchers (essentials), isolated per profile
    @Published var pinnedByProfile: [UUID: [ShortcutPin]] = [:]
    // Space-level shortcut launchers
    @Published var spacePinnedShortcuts: [UUID: [ShortcutPin]] = [:]
    // Pinned launchers encountered during load that have no profile assignment yet
    var pendingPinnedWithoutProfile: [ShortcutPin] = []
    // Transient shortcut-backed live tabs per window, keyed by shortcut pin id
    var transientShortcutTabsByWindow: [UUID: [UUID: Tab]] = [:]
    // Transient extension-owned tabs created for internal extension pages that
    // WebKit may close immediately during install/onboarding handshakes.
    var transientExtensionTabsByID: [UUID: Tab] = [:]
    var auxiliaryMiniWindowTabsByID: [UUID: Tab] = [:]
    private let structuralLookupOwner = TabStructuralLookupOwner()
    /// Emitted when tab structure changes without a corresponding `@Published` update (e.g. transient shortcut live tabs). Not used for persistence completion—`scheduleStructuralPersistence()` does not send this.
    let structuralChanges = PassthroughSubject<Void, Never>()
    private lazy var structuralPublishOwner = TabStructuralPublishOwner(structuralChanges: structuralChanges)
    var structuralLookupBatchFlushCount: Int { structuralLookupOwner.batchFlushCount }
    var structuralLookupImmediateFlushCount: Int { structuralLookupOwner.immediateFlushCount }
    private var faviconCacheObserver: NSObjectProtocol?
    private var pendingFaviconPresentationRefreshTask: Task<Void, Never>?
    // Space activation to resume after a deferred profile switch
    var pendingSpaceActivation: UUID?

    // Live essentials API for shell views that still read a tab-backed collection.
    var pinnedTabs: [Tab] {
        activeEssentialTabs(for: browserManager?.currentProfile?.id)
    }
    
    func essentialTabs(for profileId: UUID?) -> [Tab] {
        activeEssentialTabs(for: profileId)
    }

    func essentialPins(for profileId: UUID?) -> [ShortcutPin] {
        guard let profileId else { return [] }
        return Array(pinnedByProfile[profileId] ?? []).sorted { $0.index < $1.index }
    }

    func spacePinnedPins(for spaceId: UUID) -> [ShortcutPin] {
        Array(spacePinnedShortcuts[spaceId] ?? []).sorted { $0.index < $1.index }
    }

    func liveSpacePinnedTabs(for spaceId: UUID) -> [Tab] {
        transientShortcutTabsByWindow.values
            .flatMap(\.values)
            .filter { $0.spaceId == spaceId && $0.shortcutPinRole == .spacePinned }
            .sorted { lhs, rhs in
                let lhsIndex = lhs.shortcutPinId.flatMap { shortcutPin(by: $0)?.index } ?? lhs.index
                let rhsIndex = rhs.shortcutPinId.flatMap { shortcutPin(by: $0)?.index } ?? rhs.index
                if lhsIndex != rhsIndex { return lhsIndex < rhsIndex }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func selectionTabsForCurrentContext() -> [Tab] {
        let regularTabs = tabs
        let activeWindowId = browserManager?.windowRegistry?.activeWindow?.id
        let activeLauncherTab = activeWindowId
            .flatMap { activeShortcutTab(for: $0) }
            .flatMap { liveTab -> Tab? in
                guard liveTab.shortcutPinRole != .essential else { return nil }
                guard liveTab.spaceId == nil || liveTab.spaceId == currentSpace?.id else { return nil }
                return liveTab
            }

        return pinnedTabs + (activeLauncherTab.map { [$0] } ?? []) + regularTabs
    }

    func folderPinnedPins(for folderId: UUID, in spaceId: UUID) -> [ShortcutPin] {
        spacePinnedPins(for: spaceId)
            .filter { $0.folderId == folderId }
            .sorted { $0.index < $1.index }
    }

    func childFolders(of parentFolderId: UUID?, in spaceId: UUID) -> [TabFolder] {
        (foldersBySpace[spaceId] ?? [])
            .filter { $0.parentFolderId == parentFolderId }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        for pins in pinnedByProfile.values {
            if let match = pins.first(where: { $0.id == id }) { return match }
        }
        for pins in spacePinnedShortcuts.values {
            if let match = pins.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    func folder(by id: UUID) -> TabFolder? {
        for folders in foldersBySpace.values {
            if let match = folders.first(where: { $0.id == id }) { return match }
        }
        return nil
    }

    func parentContainer(for folder: TabFolder) -> TabDragManager.DragContainer {
        if let parentFolderId = folder.parentFolderId {
            return .folder(parentFolderId)
        }
        return .spacePinned(folder.spaceId)
    }

    func resolveDragTab(for id: UUID) -> Tab? {
        if let live = tab(for: id) {
            return live
        }
        if let pin = shortcutPin(by: id) {
            return dragProxyTab(for: pin)
        }
        return nil
    }

    func resolveSidebarDragPayload(for item: SumiDragItem) -> DragOperation.Payload? {
        switch item.kind {
        case .tab:
            if let pin = shortcutPin(by: item.tabId) {
                return .pin(pin)
            }
            return resolveDragTab(for: item.tabId).map { .tab($0) }
        case .folder:
            return folder(by: item.tabId).map { .folder($0) }
        case .splitGroup:
            return splitGroup(with: item.tabId).map { .splitGroup($0) }
        }
    }
    
    // Flattened pinned across all profiles for internal ops
    var allPinnedTabsAllProfiles: [Tab] {
        activeShortcutTabs(role: .essential)
    }

    // Currently active tab
    var currentTab: Tab?
    private(set) var hasLoadedInitialData = false

    func markInitialDataLoadStarted() {
        hasLoadedInitialData = false
    }

    func markInitialDataLoadFinished() {
        hasLoadedInitialData = true
    }

    init(
        browserManager: BrowserManager? = nil,
        context: ModelContext,
        loadPersistedState: Bool = true
    ) {
        self.browserManager = browserManager
        self.context = context
        let persistence = TabSnapshotRepository(container: context.container)
        self.persistence = persistence
        self.runtimeStateCoalescer = RuntimeStateCoalescer(
            debounceNanoseconds: Self.defaultRuntimeStatePersistDebounceNanoseconds,
            persistBatch: { runtimeStates in
                await persistence.persistRuntimeStates(runtimeStates)
            }
        )
        self.faviconCacheObserver = NotificationCenter.default.addObserver(
            forName: .faviconCacheUpdated,
            object: nil,
            queue: nil
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                self?.scheduleCachedFaviconPresentationRefresh()
            }
        }
        if loadPersistedState {
            Task { @MainActor in
                loadFromStore()
            }
        }
    }

    deinit {
        // MEMORY LEAK FIX: Clean up all tab references and break potential cycles
        MainActor.assumeIsolated {
            scheduledStructuralPersistTask?.cancel()
            scheduledStructuralPersistTask = nil
            startupRestoreTask?.cancel()
            startupRestoreTask = nil
            pendingFaviconPresentationRefreshTask?.cancel()
            pendingFaviconPresentationRefreshTask = nil
            if let faviconCacheObserver {
                NotificationCenter.default.removeObserver(faviconCacheObserver)
                self.faviconCacheObserver = nil
            }
            tabsBySpace.removeAll()
            splitGroups.removeAll()
            spacePinnedShortcuts.removeAll()
            foldersBySpace.removeAll()
            pinnedByProfile.removeAll()
            pendingPinnedWithoutProfile.removeAll()
            transientShortcutTabsByWindow.removeAll()
            transientExtensionTabsByID.removeAll()
            structuralLookupOwner.removeAll()
            spaces.removeAll()
            currentTab = nil
            currentSpace = nil
            browserManager = nil
        }

        RuntimeDiagnostics.debug("Cleaned up all tab resources.", category: "TabManager")
    }

    // MARK: - Convenience

    var tabs: [Tab] {
        guard let s = currentSpace else { return [] }
        // `setTabs` keeps each space’s array sorted by index (and id tie-break); copy for callers that mutate.
        return regularTabCollectionOwner.tabs(in: s)
    }

    func setTabs(_ items: [Tab], for spaceId: UUID) {
        let previousTabs = tabsBySpace[spaceId] ?? []
        let sortedItems = items.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        tabsBySpace[spaceId] = sortedItems
        markRegularTabsSnapshotDirty(for: spaceId)
        recordRegularTabsStructuralChange(previous: previousTabs, current: sortedItems)
        queueTabLookupEntries(removing: previousTabs, with: sortedItems)
        requestStructuralPublish()
    }

    func setFolders(_ items: [TabFolder], for spaceId: UUID) {
        let previousFolders = foldersBySpace[spaceId] ?? []
        foldersBySpace[spaceId] = items
        markFoldersSnapshotDirty(for: spaceId)
        recordFoldersStructuralChange(previous: previousFolders, current: items)
        requestStructuralPublish()
    }

    func setPinnedTabs(_ items: [ShortcutPin], for profileId: UUID) {
        let previousPins = pinnedByProfile[profileId] ?? []
        pinnedByProfile[profileId] = items
        SumiFaviconSystem.shared.syncShortcutPins(Array(pinnedByProfile.values.joined()) + Array(spacePinnedShortcuts.values.joined()))
        markPinnedSnapshotDirty(for: profileId)
        recordShortcutPinsStructuralChange(previous: previousPins, current: items)
        requestStructuralPublish()
    }

    func setSpacePinnedShortcuts(_ items: [ShortcutPin], for spaceId: UUID) {
        let previousPins = spacePinnedShortcuts[spaceId] ?? []
        spacePinnedShortcuts[spaceId] = items
        SumiFaviconSystem.shared.syncShortcutPins(Array(pinnedByProfile.values.joined()) + Array(spacePinnedShortcuts.values.joined()))
        markSpacePinnedSnapshotDirty(for: spaceId)
        recordShortcutPinsStructuralChange(previous: previousPins, current: items)
        requestStructuralPublish()
    }

    func notifyTransientShortcutStateChanged() {
        queueTransientTabLookupRefresh()
        requestStructuralPublish()
    }

    private func scheduleCachedFaviconPresentationRefresh() {
        pendingFaviconPresentationRefreshTask?.cancel()
        pendingFaviconPresentationRefreshTask = Task { @MainActor [weak self] in
            do {
                try await Task.sleep(nanoseconds: Self.faviconPresentationRefreshDebounceNanoseconds)
            } catch {
                return
            }
            guard !Task.isCancelled else { return }

            self?.pendingFaviconPresentationRefreshTask = nil
            self?.refreshCachedFaviconPresentation()
        }
    }

    private func refreshCachedFaviconPresentation() {
        let tabsNeedingRefresh = Array(tabsBySpace.values.joined())
            + Array(transientShortcutTabsByWindow.values.joined().map(\.value))
        for tab in tabsNeedingRefresh where tab.faviconIsTemplateGlobePlaceholder {
            _ = tab.applyCachedFaviconOrPlaceholder(for: tab.url)
        }
        requestStructuralPublish()
    }

    private var structuralLookupSnapshot: TabStructuralLookupSnapshot {
        TabStructuralLookupSnapshot(
            tabsBySpace: tabsBySpace,
            transientShortcutTabsByWindow: transientShortcutTabsByWindow,
            transientExtensionTabsByID: transientExtensionTabsByID,
            auxiliaryMiniWindowTabsByID: auxiliaryMiniWindowTabsByID
        )
    }

    func tab(for id: UUID) -> Tab? {
        structuralLookupOwner.tab(for: id, snapshot: structuralLookupSnapshot)
    }

    private func rebuildTabLookup() {
        structuralLookupOwner.rebuild(with: structuralLookupSnapshot)
    }

    func rebuildTabLookupForRestore() {
        rebuildTabLookup()
    }

    @discardableResult
    func withStructuralUpdateTransaction<T>(_ operation: () throws -> T) rethrows -> T {
        try structuralPublishOwner.withTransaction(
            flushPendingLookupBatch: { flushPendingStructuralLookupBatchIfNeeded() },
            operation
        )
    }

    func requestStructuralPublish() {
        structuralPublishOwner.requestPublish()
    }

    private func queueTabLookupEntries(removing previousTabs: [Tab], with currentTabs: [Tab]) {
        structuralLookupOwner.queueEntries(
            removing: previousTabs,
            with: currentTabs,
            batching: structuralPublishOwner.isBatching
        )
    }

    private func queueTransientTabLookupRefresh() {
        structuralLookupOwner.queueTransientRefresh(
            snapshot: structuralLookupSnapshot,
            batching: structuralPublishOwner.isBatching
        )
    }

    private func flushPendingStructuralLookupBatchIfNeeded() {
        structuralLookupOwner.flushBatchIfNeeded(snapshot: structuralLookupSnapshot)
    }
    typealias SpacePinnedTopLevelItem = SpacePinnedShortcutOrderOwner.TopLevelItem

    func normalizedSpacePinnedShortcuts(_ items: [ShortcutPin]) -> [ShortcutPin] {
        SpacePinnedShortcutOrderOwner.normalizedShortcuts(
            items,
            foldersBySpace: foldersBySpace
        )
    }

    enum FolderChildVisualItem: Hashable {
        case folder(UUID)
        case shortcut(UUID)
        case splitGroup(UUID)

        var id: UUID {
            switch self {
            case .folder(let id), .shortcut(let id), .splitGroup(let id):
                return id
            }
        }
    }

    func folderChildVisualItems(for folderId: UUID, in spaceId: UUID) -> [FolderChildVisualItem] {
        splitGroupVisualOrderingResolver(for: spaceId).folderItems(for: folderId).map { item in
            switch item {
            case .folder(let id):
                return .folder(id)
            case .shortcut(let id):
                return .shortcut(id)
            case .splitGroup(let id):
                return .splitGroup(id)
            }
        }
    }

    func folderDirectChildCount(for folderId: UUID, in spaceId: UUID) -> Int {
        folderChildVisualItems(for: folderId, in: spaceId).count
    }

    func folderRecursiveChildCount(for folderId: UUID, in spaceId: UUID) -> Int {
        func countChildren(of parentId: UUID, visited: Set<UUID>) -> Int {
            guard visited.contains(parentId) == false else { return 0 }
            var nextVisited = visited
            nextVisited.insert(parentId)

            let childFolders = childFolders(of: parentId, in: spaceId)
            let directPinsCount = folderPinnedPins(for: parentId, in: spaceId).count
            let nestedCount = childFolders.reduce(0) { total, childFolder in
                total + 1 + countChildren(of: childFolder.id, visited: nextVisited)
            }
            return directPinsCount + nestedCount
        }

        return countChildren(of: folderId, visited: [])
    }

    func topLevelSpacePinnedItems(for spaceId: UUID) -> [SpacePinnedTopLevelItem] {
        SpacePinnedShortcutOrderOwner.topLevelItems(
            for: spaceId,
            foldersBySpace: foldersBySpace,
            spacePinnedShortcuts: spacePinnedShortcuts
        )
    }

    func applyTopLevelSpacePinnedOrder(
        _ items: [SpacePinnedTopLevelItem],
        for spaceId: UUID
    ) {
        withStructuralUpdateTransaction {
            let plan = SpacePinnedShortcutOrderOwner.topLevelOrderPlan(
                items,
                for: spaceId,
                foldersBySpace: foldersBySpace,
                spacePinnedShortcuts: spacePinnedShortcuts
            )
            for placement in plan.folderPlacements {
                placement.folder.index = placement.index
                placement.folder.spaceId = placement.spaceId
                placement.folder.parentFolderId = placement.parentFolderId
            }
            let finalFolders = (plan.orderedFolders + plan.remainingFolders).sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
            setFolders(finalFolders, for: spaceId)

            let finalPins = normalizedSpacePinnedShortcuts(plan.folderPins + plan.orderedTopLevelPins)
            setSpacePinnedShortcuts(finalPins, for: spaceId)
        }
    }

    func insertTopLevelSpacePinnedShortcut(
        _ pin: ShortcutPin,
        in spaceId: UUID,
        at targetIndex: Int
    ) -> ShortcutPin? {
        let items = SpacePinnedShortcutOrderOwner.insertingTopLevelShortcut(
            pin,
            in: topLevelSpacePinnedItems(for: spaceId),
            at: targetIndex
        )
        applyTopLevelSpacePinnedOrder(items, for: spaceId)
        return spacePinnedShortcuts[spaceId]?.first(where: { $0.id == pin.id })
    }

    func adjustedSameContainerInsertionIndex(
        currentIndex: Int,
        proposedIndex: Int
    ) -> Int {
        SpacePinnedShortcutOrderOwner.adjustedSameContainerInsertionIndex(
            currentIndex: currentIndex,
            proposedIndex: proposedIndex
        )
    }

    @discardableResult
    func reorderTopLevelSpacePinnedShortcut(
        _ pin: ShortcutPin,
        in spaceId: UUID,
        to targetIndex: Int
    ) -> ShortcutPin? {
        switch SpacePinnedShortcutOrderOwner.reorderingTopLevelItem(
            id: pin.id,
            in: topLevelSpacePinnedItems(for: spaceId),
            to: targetIndex
        ) {
        case .missing:
            return nil
        case .unchanged:
            return pin
        case .moved(let items):
            applyTopLevelSpacePinnedOrder(items, for: spaceId)
            return spacePinnedShortcuts[spaceId]?.first(where: { $0.id == pin.id })
        }
    }

    @discardableResult
    func reorderFolderInTopLevelPinned(
        _ folder: TabFolder,
        in spaceId: UUID,
        to targetIndex: Int
    ) -> Bool {
        switch SpacePinnedShortcutOrderOwner.reorderingTopLevelItem(
            id: folder.id,
            in: topLevelSpacePinnedItems(for: spaceId),
            to: targetIndex
        ) {
        case .missing, .unchanged:
            return false
        case .moved(let items):
            applyTopLevelSpacePinnedOrder(items, for: spaceId)
            scheduleStructuralPersistence()
            return true
        }
    }

    func withSpacePinnedShortcutGroup(
        for spaceId: UUID,
        folderId: UUID?,
        _ mutate: (inout [ShortcutPin]) -> Void
    ) {
        let allPins = spacePinnedShortcuts[spaceId] ?? []
        let rebuilt = SpacePinnedShortcutOrderOwner.mutatingShortcutGroup(
            in: allPins,
            folderId: folderId,
            foldersBySpace: foldersBySpace,
            mutate
        )
        setSpacePinnedShortcuts(rebuilt, for: spaceId)
    }

    func attach(_ tab: Tab) {
        tab.browserManager = browserManager
        tab.sumiSettings = sumiSettings
        structuralLookupOwner.attach(tab)
    }

    func detach(_ tab: Tab) {
        structuralLookupOwner.detach(tab)
    }

    // Public accessor for managers that need to iterate tabs (e.g., privacy, rules updates)
    func allTabs() -> [Tab] {
        structuralLookupOwner.rebuildIfEmpty(with: structuralLookupSnapshot)

        let normals = regularTabCollectionOwner.allTabs(in: spaces)
        return transientShortcutTabsByWindow.values.flatMap(\.values)
            + Array(transientExtensionTabsByID.values)
            + normals
    }

    /// Profile-filtered union of pinned, space-pinned and regular tabs.
    func allTabsForCurrentProfile() -> [Tab] {
        guard let pid = browserManager?.currentProfile?.id else {
            return allTabs()
        }
        let spaceIds = Set(spaces.filter { $0.profileId == pid }.map { $0.id })
        let pinned = activeEssentialTabs(for: pid)
        let spacePinned = transientShortcutTabsByWindow.values
            .flatMap(\.values)
            .filter { tab in
                guard tab.shortcutPinRole == .spacePinned, let sid = tab.spaceId else { return false }
                return spaceIds.contains(sid)
            }
        let regular = regularTabCollectionOwner
            .allTabs(in: spaces.filter { spaceIds.contains($0.id) })
        return pinned + spacePinned + regular
    }

    private func contains(_ tab: Tab) -> Bool {
        if activeShortcutTabs().contains(where: { $0.id == tab.id }) {
            return true
        }
        if allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) {
            return true
        }
        if regularTabCollectionOwner.contains(tab) {
            return true
        }
        return false
    }

    // MARK: - Container Membership Helpers
    /// True if the tab is globally pinned (Essentials) in any profile.
    func isGlobalPinned(_ tab: Tab) -> Bool {
        return allPinnedTabsAllProfiles.contains { $0.id == tab.id }
    }

    /// True if the tab is pinned at the space level within its space.
    func isSpacePinned(_ tab: Tab) -> Bool {
        if tab.shortcutPinRole == .spacePinned {
            return true
        }
        guard let shortcutId = tab.shortcutPinId,
              let pin = shortcutPin(by: shortcutId) else { return false }
        return pin.role == .spacePinned
    }

    func regularChildInsertionIndex(openedFrom sourceTab: Tab?, in targetSpace: Space?) -> Int? {
        regularTabCollectionOwner.childInsertionIndex(openedFrom: sourceTab, in: targetSpace)
    }

    /// Create a new regular tab duplicating the source tab's URL/name and insert near an anchor tab.
    /// - Parameters:
    ///   - source: The tab to duplicate (pinned/space-pinned or regular).
    ///   - anchor: A regular tab used to decide target space and placement. If nil, falls back to currentSpace.
    ///   - placeAfterAnchor: If true, insert right after the anchor's index; otherwise at the anchor's index.
    /// - Returns: The newly created regular Tab.
    @discardableResult
    func duplicateAsRegularForSplit(from source: Tab, anchor: Tab?, placeAfterAnchor: Bool = true) -> Tab {
        return withStructuralUpdateTransaction {
            // Resolve target space: prefer the anchor's space, else currentSpace.
            let targetSpace: Space = {
                if let a = anchor, let sid = a.spaceId, let sp = spaces.first(where: { $0.id == sid }) { return sp }
                return currentSpace ?? ensureDefaultSpaceIfNeeded()
            }()

            // Build the duplicate with the same URL/name; favicon will refresh from URL.
            let newTab = Tab(
                url: source.url,
                name: source.name,
                favicon: "globe",
                spaceId: targetSpace.id,
                index: 0,
                browserManager: browserManager
            )

            let insertionIndex = anchor
                .flatMap { anchor in
                    regularTabCollectionOwner.firstIndex(of: anchor, in: targetSpace.id)
                }
                .map { $0 + (placeAfterAnchor ? 1 : 0) }
            addTab(newTab, regularInsertionIndex: insertionIndex)

            return newTab
        }
    }

    // MARK: - Folder Management

    func createFolder(for spaceId: UUID, name: String = "New Folder") -> TabFolder {
        folderService.createFolder(for: spaceId, name: name)
    }

    @discardableResult
    func createFolder(
        for spaceId: UUID,
        parentFolderId: UUID?,
        name: String = "New Folder"
    ) -> TabFolder? {
        folderService.createFolder(for: spaceId, parentFolderId: parentFolderId, name: name)
    }

    func renameFolder(_ folderId: UUID, newName: String) {
        folderService.renameFolder(folderId, newName: newName)
    }

    func updateFolderIcon(_ folderId: UUID, icon: String) {
        folderService.updateFolderIcon(folderId, icon: icon)
    }

    func setFolder(_ folderId: UUID, open isOpen: Bool) {
        folderService.setFolder(folderId, open: isOpen)
    }

    func toggleFolderOpenState(_ folderId: UUID) {
        folderService.toggleFolderOpenState(folderId)
    }

    func deleteFolder(_ folderId: UUID) {
        folderService.deleteFolder(folderId)
    }

    func ungroupFolder(_ folderId: UUID) {
        folderService.ungroupFolder(folderId)
    }

    func folders(for spaceId: UUID) -> [TabFolder] {
        folderService.folders(for: spaceId)
    }

    func openFolderIfNeeded(_ folderId: UUID) {
        folderService.setFolder(folderId, open: true)
    }

    func setAllFolders(open isOpen: Bool, in spaceId: UUID) {
        folderService.setAllFolders(open: isOpen, in: spaceId)
    }

    func moveTabToFolder(tab: Tab, folderId: UUID) {
        folderService.moveTabToFolder(tab: tab, folderId: folderId)
    }

    // MARK: - Tab Management (Normal within current space)

    func addTab(_ tab: Tab, regularInsertionIndex: Int? = nil) {
        withStructuralUpdateTransaction {
            attach(tab)
            if contains(tab) { return }

            if tab.spaceId == nil {
                tab.spaceId = currentSpace?.id
            }
            guard let sid = tab.spaceId else {
                RuntimeDiagnostics.debug("Skipping addTab for '\(tab.name)' because no spaceId was resolved.", category: "TabManager")
                return
            }
            insertRegularTab(tab, in: sid, at: regularInsertionIndex)
        
            // Load the tab in compositor if it's the current tab
            if tab.id == currentTab?.id {
                if let browserManager,
                   let activeWindow = browserManager.windowRegistry?.activeWindow {
                    browserManager.materializeVisibleTabWebViewIfNeeded(tab, in: activeWindow)
                } else {
                    browserManager?.compositorManager.loadTab(tab)
                }
            }
        
            RuntimeDiagnostics.debug("Added regular tab '\(tab.name)' to space \(sid.uuidString).", category: "TabManager")
            scheduleStructuralPersistence()
        }
    }

    @discardableResult
    func adoptGlanceTab(
        _ tab: Tab,
        sourceTab: Tab?,
        in space: Space? = nil
    ) -> Tab {
        withStructuralUpdateTransaction {
            attach(tab)
            if contains(tab) { return tab }

            let targetSpace = resolvedTargetSpace(
                preferred: space,
                fallbackSpaceId: sourceTab?.spaceId
            )
            backfillTargetSpaceProfileIfNeeded(
                targetSpace,
                profileId: tab.profileId ?? browserManager?.currentProfile?.id
            )

            let insertionIndex: Int? = {
                if let sourceTab,
                   sourceTab.spaceId == targetSpace.id,
                   let sourceIndex = regularTabCollectionOwner.firstIndex(of: sourceTab, in: targetSpace.id) {
                    return sourceIndex + 1
                }
                if sourceTab?.isPinned == true || sourceTab?.shortcutPinRole == .essential {
                    return 0
                }
                return nil
            }()

            if let currentURL = tab.existingWebView?.url {
                tab.url = currentURL
            }
            insertRegularTab(tab, in: targetSpace.id, at: insertionIndex)
            scheduleStructuralPersistence()
            return tab
        }
    }

    private func insertRegularTab(_ tab: Tab, in spaceId: UUID, at insertionIndex: Int?) {
        regularTabCollectionOwner.insert(tab, in: spaceId, at: insertionIndex)
    }

    private func resolvedTargetSpace(preferred space: Space?, fallbackSpaceId: UUID? = nil) -> Space {
        space
            ?? fallbackSpaceId.flatMap { spaceId in
                spaces.first(where: { $0.id == spaceId })
            }
            ?? currentSpace
            ?? ensureDefaultSpaceIfNeeded()
    }

    private var defaultProfileIdForSpaceBootstrap: UUID? {
        browserManager?.currentProfile?.id
            ?? browserManager?.profileManager.profiles.first?.id
    }

    @discardableResult
    private func backfillTargetSpaceProfileIfNeeded(
        _ targetSpace: Space,
        profileId: UUID?
    ) -> Bool {
        guard targetSpace.profileId == nil, let profileId else { return false }
        targetSpace.profileId = profileId
        markAllSpacesStructurallyDirty()
        return true
    }

    func isTransientExtensionTab(_ tab: Tab) -> Bool {
        transientExtensionTabsByID[tab.id] != nil
    }

    @discardableResult
    func createTransientExtensionTab(
        url: String,
        in space: Space? = nil,
        webExtensionContextOverride: WKWebExtensionContext?
    ) -> Tab {
        let settings = sumiSettings ?? browserManager?.sumiSettings
        let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        let normalizedUrl = normalizeURL(url, queryTemplate: template)
        let validURL = URL(string: normalizedUrl) ?? SumiSurface.emptyTabURL

        let targetSpace = resolvedTargetSpace(preferred: space)
        if backfillTargetSpaceProfileIfNeeded(targetSpace, profileId: defaultProfileIdForSpaceBootstrap) {
            scheduleStructuralPersistence()
        }

        let sid = targetSpace.id
        let nextIndex = regularTabCollectionOwner.appendIndex(in: sid)
        let tab = Tab(
            url: validURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: sid,
            index: nextIndex,
            browserManager: browserManager
        )
        tab.profileId = targetSpace.profileId
        tab.webExtensionContextOverride = webExtensionContextOverride
        attach(tab)
        transientExtensionTabsByID[tab.id] = tab
        structuralLookupOwner.insertTransientExtensionTab(tab)
        return tab
    }

    @discardableResult
    func createAuxiliaryMiniWindowTab(
        openerTab: Tab?,
        profileId: UUID? = nil,
        urlString: String? = nil,
        webExtensionContextOverride: WKWebExtensionContext? = nil
    ) -> Tab {
        let blankURL = SumiSurface.emptyTabURL
        let resolvedURL = urlString.flatMap { URL(string: $0) } ?? blankURL
        let resolvedProfileId = profileId
            ?? openerTab?.profileId
            ?? openerTab?.resolveProfile()?.id
            ?? browserManager?.currentProfile?.id

        let tab = Tab(
            url: resolvedURL,
            name: "Popup",
            favicon: "globe",
            spaceId: openerTab?.spaceId,
            index: -1,
            browserManager: browserManager
        )
        tab.isAuxiliaryMiniWindow = true
        tab.profileId = resolvedProfileId
        tab.webExtensionContextOverride = webExtensionContextOverride
        attach(tab)
        auxiliaryMiniWindowTabsByID[tab.id] = tab
        return tab
    }

    func removeAuxiliaryMiniWindowTab(_ tab: Tab) {
        auxiliaryMiniWindowTabsByID.removeValue(forKey: tab.id)
        structuralLookupOwner.remove(tab.id)
        browserManager?.compositorManager.unloadTab(tab)
        browserManager?.webViewCoordinator?.removeAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: true
        )
        detach(tab)
        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )
    }

    func isAuxiliaryMiniWindowTab(_ tab: Tab) -> Bool {
        auxiliaryMiniWindowTabsByID[tab.id] != nil
    }

    @discardableResult
    func promoteTransientExtensionTab(
        _ tab: Tab,
        in space: Space? = nil,
        activate: Bool = false
    ) -> Bool {
        guard transientExtensionTabsByID.removeValue(forKey: tab.id) != nil else {
            return false
        }
        structuralLookupOwner.stopTrackingTransientTab(tab.id)

        let targetSpace = space
            ?? tab.spaceId.flatMap { spaceId in
                spaces.first(where: { $0.id == spaceId })
            }
            ?? currentSpace
            ?? ensureDefaultSpaceIfNeeded()
        insertRegularTab(tab, in: targetSpace.id, at: nil)
        scheduleStructuralPersistence()
        if activate {
            setActiveTab(tab)
        }
        return true
    }

    private func cleanupRemovedTransientExtensionTab(_ tab: Tab) {
        browserManager?.extensionsModule.notifyTabClosedIfLoaded(tab)
        browserManager?.compositorManager.unloadTab(tab)
        browserManager?.webViewCoordinator?.removeAllWebViews(
            for: tab,
            closeActiveFullscreenMedia: true
        )
        detach(tab)
        NotificationCenter.default.post(
            name: .sumiTabLifecycleDidChange,
            object: tab
        )
    }

    func removeTab(_ id: UUID) {
        withStructuralUpdateTransaction {
            // Notify SplitViewManager about tab closure to prevent zombie state
            browserManager?.splitManager.handleTabClosure(id)
            cancelRuntimeStatePersistence(for: id)
        
            let wasCurrent = (currentTab?.id == id)
            var removed: Tab?
            var removedSpaceId: UUID?
            var removedIndexInCurrentSpace: Int?

            if let transientExtensionTab = transientExtensionTabsByID.removeValue(forKey: id) {
                structuralLookupOwner.removeTransientExtensionTab(id)
                cleanupRemovedTransientExtensionTab(transientExtensionTab)
                return
            }

            if auxiliaryMiniWindowTabsByID[id] != nil {
                browserManager?.closeAuxiliaryMiniWindow(
                    for: tab(for: id) ?? auxiliaryMiniWindowTabsByID[id]!,
                    reason: .extensionRequestedClose
                )
                return
            }

            if let removal = regularTabCollectionOwner.remove(
                id,
                in: spaces,
                currentSpaceId: currentSpace?.id
            ) {
                removed = removal.tab
                removedSpaceId = removal.spaceId
                removedIndexInCurrentSpace = removal.indexInCurrentSpace
            }
            if removed == nil,
               let (windowId, pinId, tab) = transientShortcutTabsByWindow.lazy
                    .compactMap({ windowId, tabsByPin -> (UUID, UUID, Tab)? in
                        guard let match = tabsByPin.first(where: { $0.value.id == id }) else { return nil }
                        return (windowId, match.key, match.value)
                    })
                    .first
            {
                transientShortcutTabsByWindow[windowId]?.removeValue(forKey: pinId)
                if transientShortcutTabsByWindow[windowId]?.isEmpty == true {
                    transientShortcutTabsByWindow.removeValue(forKey: windowId)
                }
                notifyTransientShortcutStateChanged()
                removed = tab
            }

            guard let tab = removed else { return }

            browserManager?.extensionsModule.notifyTabClosedIfLoaded(tab)

            browserManager?.windowRegistry?.windows.values.forEach { windowState in
                windowState.removeFromRegularTabHistory(tab.id)
            }

            captureRecentlyClosedTab(tab, spaceId: removedSpaceId)

            // Force unload the tab from compositor before removing
            browserManager?.compositorManager.unloadTab(tab)
            browserManager?.webViewCoordinator?.removeAllWebViews(
                for: tab,
                closeActiveFullscreenMedia: true
            )
            detach(tab)

            NotificationCenter.default.post(
                name: .sumiTabLifecycleDidChange,
                object: tab
            )

            if wasCurrent {
                if tab.spaceId == nil {
                    // Tab was global pinned
                    if !pinnedTabs.isEmpty {
                        currentTab = pinnedTabs.last
                    } else if let cs = currentSpace {
                        let spacePinned = liveSpacePinnedTabs(for: cs.id)
                        let arr = regularTabCollectionOwner.tabs(in: cs.id)
                        currentTab = spacePinned.last ?? arr.last
                    } else {
                        currentTab = nil
                    }
                } else if let cs = currentSpace {
                    // Tab was in a space
                    let spacePinned = liveSpacePinnedTabs(for: cs.id)
                    let arr = regularTabCollectionOwner.tabs(in: cs.id)

                    if let i = removedIndexInCurrentSpace {
                        // Try to select adjacent tab
                        let allSpaceTabs = spacePinned + arr
                        if !allSpaceTabs.isEmpty {
                            let newIndex = min(i, allSpaceTabs.count - 1)
                            currentTab = allSpaceTabs.indices.contains(newIndex)
                                ? allSpaceTabs[newIndex]
                                : allSpaceTabs.first
                        } else if !pinnedTabs.isEmpty {
                            currentTab = pinnedTabs.last
                        } else {
                            currentTab = nil
                        }
                    } else {
                        // Fallback to last tab
                        currentTab = arr.last ?? spacePinned.last ?? pinnedTabs.last
                    }
                }
            }

            scheduleStructuralPersistence()

            // Validate window states after tab removal
            browserManager?.validateWindowStates()
        }
    }

    func setActiveTab(_ tab: Tab) {
        guard contains(tab) else {
            return
        }
        let previous = currentTab
        if previous?.id != tab.id {
            currentTab = tab
        }

        // Update active split group state for windows that currently display this tab.
        if let bm = browserManager {
            for (windowId, windowState) in bm.windowRegistry?.windows ?? [:] {
                if bm.splitManager.visibleTabIds(for: windowId).contains(tab.id) {
                    bm.splitManager.updateActiveSide(for: tab.id, in: windowId)
                    if windowState.currentTabId != tab.id {
                        windowState.currentTabId = tab.id
                    }
                }
            }
        }

        updateActiveTabSpaceSelectionState(for: tab, refreshCurrentSpaceReference: false)

        if previous?.id != tab.id {
            browserManager?.extensionsModule.notifyTabActivatedIfLoaded(
                newTab: tab,
                previous: previous
            )
        }
        
        persistSelection()
    }
    
    /// Update only the global tab state without triggering UI operations
    /// Used when BrowserManager.selectTab() has already handled all UI concerns
    func updateActiveTabState(_ tab: Tab) {
        guard contains(tab) else {
            return
        }
        currentTab = tab
        updateActiveTabSpaceSelectionState(for: tab, refreshCurrentSpaceReference: true)
        
        persistSelection()
    }

    private func updateActiveTabSpaceSelectionState(
        for tab: Tab,
        refreshCurrentSpaceReference: Bool
    ) {
        var didChangeSpacePersistenceState = false
        if let sid = tab.spaceId, let space = spaces.first(where: { $0.id == sid }) {
            if space.activeTabId != tab.id {
                space.activeTabId = tab.id
                didChangeSpacePersistenceState = true
            }
            if refreshCurrentSpaceReference || currentSpace?.id != space.id {
                currentSpace = space
            }
        } else if let cs = currentSpace {
            if cs.activeTabId != tab.id {
                cs.activeTabId = tab.id
                didChangeSpacePersistenceState = true
            }
        }
        if didChangeSpacePersistenceState {
            markSpacesSnapshotDirty()
        }
    }

    @discardableResult
    func createNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        webExtensionContextOverride: WKWebExtensionContext? = nil,
        regularInsertionIndex: Int? = nil
    ) -> Tab {
        return withStructuralUpdateTransaction {
            let settings = sumiSettings ?? browserManager?.sumiSettings
            let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
            let normalizedUrl = normalizeURL(url, queryTemplate: template)
            guard let validURL = URL(string: normalizedUrl)
            else {
                RuntimeDiagnostics.debug("Invalid URL '\(url)' while creating a new tab; falling back to Sumi empty surface.", category: "TabManager")
                return createNewTab(
                    in: space,
                    activate: activate,
                    webViewConfigurationOverride: webViewConfigurationOverride,
                    webExtensionContextOverride: webExtensionContextOverride,
                    regularInsertionIndex: regularInsertionIndex
                )
            }

            let targetSpace = resolvedTargetSpace(preferred: space)
            if backfillTargetSpaceProfileIfNeeded(targetSpace, profileId: defaultProfileIdForSpaceBootstrap) {
                scheduleStructuralPersistence()
            }
            let sid = targetSpace.id

            let nextIndex = regularInsertionIndex
                ?? regularTabCollectionOwner.appendIndex(in: sid)

            let newTab = Tab(
                url: validURL,
                name: "New Tab",
                favicon: "globe",
                spaceId: sid,
                index: nextIndex,
                browserManager: browserManager
            )
            newTab.profileId = targetSpace.profileId
            newTab.webExtensionContextOverride = webExtensionContextOverride
            if let webViewConfigurationOverride {
                newTab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
            }
            addTab(newTab, regularInsertionIndex: regularInsertionIndex)
            if activate {
                setActiveTab(newTab)
            }
            return newTab
        }
    }
    
    // MARK: - Ephemeral Tab Creation (Incognito)
    
    /// Create a new ephemeral tab in an incognito window
    /// These tabs are NOT persisted and are stored in window state
    @discardableResult
    func createEphemeralTab(
        url: URL,
        in windowState: BrowserWindowState,
        profile: Profile
    ) -> Tab {
        let nextIndex = windowState.ephemeralTabs.map(\.index).max().map { $0 + 1 } ?? 0
        let newTab = Tab(
            url: url,
            name: url.host ?? "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: nextIndex,
            browserManager: browserManager
        )
        newTab.profileId = profile.id
        
        // Add to window's ephemeral tabs (NOT to persistent tabs)
        windowState.ephemeralTabs.append(newTab)
        windowState.currentTabId = newTab.id
        
        RuntimeDiagnostics.emit("🔒 [TabManager] Created ephemeral tab: \(newTab.id) in window: \(windowState.id)")
        
        return newTab
    }

    // Create a new tab with an existing WebView (used for Glance transfers)
    @discardableResult
    func createNewTabWithWebView(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        in space: Space? = nil,
        existingWebView: WKWebView? = nil
    ) -> Tab {
        return withStructuralUpdateTransaction {
            let settings = sumiSettings ?? browserManager?.sumiSettings
            let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
            let normalizedUrl = normalizeURL(url, queryTemplate: template)
            guard let validURL = URL(string: normalizedUrl)
            else {
                RuntimeDiagnostics.debug("Invalid URL '\(url)' while creating a WebView-backed tab; falling back to Sumi empty surface.", category: "TabManager")
                return createNewTab(in: space)
            }

            let targetSpace = resolvedTargetSpace(preferred: space)
            if backfillTargetSpaceProfileIfNeeded(targetSpace, profileId: defaultProfileIdForSpaceBootstrap) {
                scheduleStructuralPersistence()
            }
            let sid = targetSpace.id

            let nextIndex = regularTabCollectionOwner.appendIndex(in: sid)

            let newTab = Tab(
                url: validURL,
                name: "New Tab",
                favicon: "globe",
                spaceId: sid,
                index: nextIndex,
                browserManager: browserManager,
                existingWebView: existingWebView
            )
            addTab(newTab)
            setActiveTab(newTab)
            return newTab
        }
    }

    // Create a new blank tab intended to host a popup window. The returned tab's
    // WKWebView is returned to WebKit so it can load popup content. No initial
    // navigation is performed to preserve window.opener scripting semantics.
    @discardableResult
    func createPopupTab(
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil,
        regularInsertionIndex: Int? = nil
    ) -> Tab {
        return withStructuralUpdateTransaction {
            let targetSpace = resolvedTargetSpace(preferred: space)
            if backfillTargetSpaceProfileIfNeeded(targetSpace, profileId: defaultProfileIdForSpaceBootstrap) {
                scheduleStructuralPersistence()
            }
            let sid = targetSpace.id
            let resolvedIndex = regularInsertionIndex
                .map { regularTabCollectionOwner.clampedInsertionIndex($0, in: sid) }
                ?? regularTabCollectionOwner.appendIndex(in: sid)

            guard let blankURL = URL(string: "about:blank") else {
                preconditionFailure("TabManager: invalid about:blank URL")
            }
            let newTab = Tab(
                url: blankURL,
                name: "New Tab",
                favicon: "globe",
                spaceId: sid,
                index: resolvedIndex,
                browserManager: browserManager
            )
            newTab.isPopupHost = true
            if let webViewConfigurationOverride {
                newTab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
            }
            attach(newTab)
            insertRegularTab(newTab, in: sid, at: resolvedIndex)
            scheduleStructuralPersistence()
            if activate {
                setActiveTab(newTab)
            }
            return newTab
        }
    }

    // Ensure a default space exists and is active; create a Personal space if needed
    private func ensureDefaultSpaceIfNeeded() -> Space {
        if let cs = currentSpace { return cs }
        if spaces.isEmpty {
            let resolvedProfileId = browserManager?.currentProfile?.id
            let personal = Space(
                name: "Personal",
                icon: "🏠",
                workspaceTheme: .default,
                profileId: resolvedProfileId
            )
            spaces.append(personal)
            markAllSpacesStructurallyDirty()
            setTabs([], for: personal.id)
            currentSpace = personal
            scheduleStructuralPersistence()
            return personal
        } else {
            currentSpace = spaces.first
            return currentSpace ?? spaces.first ?? createSpace(name: "Personal")
        }
    }

    func clearRegularTabs(for spaceId: UUID) {
        withStructuralUpdateTransaction {
            let tabs = regularTabCollectionOwner.tabs(in: spaceId)
            guard !tabs.isEmpty else { return }

            RuntimeDiagnostics.emit("🧹 [TabManager] Clearing \(tabs.count) regular tabs for space \(spaceId)")

            let inactiveRegular = tabs.filter { $0.id != currentTab?.id }
            if !inactiveRegular.isEmpty {
                for tab in inactiveRegular {
                    removeTab(tab.id)
                }
                return
            }
            if let active = currentTab,
               active.spaceId == spaceId,
               tabs.contains(where: { $0.id == active.id }) {
                removeTab(active.id)
            }
        }
    }
    
    // Helper to safely mutate current profile's pinned array with reindexing
    var structuralPersistenceGeneration: Int = 0
    var scheduledStructuralPersistTask: Task<Void, Never>?
    var structuralPersistRequestID: UInt64 = 0
    let structuralPersistDebounceNanoseconds: UInt64 = 250_000_000
    var structuralDirtySet = TabStructuralDirtySet()
    var snapshotCache = TabManagerSnapshotCache()
    var startupRestoreTask: Task<Void, Never>?
    static let defaultRuntimeStatePersistDebounceNanoseconds: UInt64 = 250_000_000
}

extension TabManager {
    nonisolated func reattachBrowserManager(_ bm: BrowserManager) {
        Task { @MainActor in
            await _reattachBrowserManager(bm)
        }
    }
    
    private func _reattachBrowserManager(_ bm: BrowserManager) async {
        self.browserManager = bm
        let visibleTabs = selectionTabsForCurrentContext()
        for t in visibleTabs {
            t.browserManager = bm
        }
        // Assign any pinned tabs that were loaded without a profile once currentProfile is known
        if let currentProfileId = browserManager?.currentProfile?.id,
           !pendingPinnedWithoutProfile.isEmpty {
            withPinnedArray(for: currentProfileId) { arr in
                arr.append(contentsOf: pendingPinnedWithoutProfile)
            }
            pendingPinnedWithoutProfile.removeAll()
            scheduleStructuralPersistence()
        }
        if let current = self.currentTab {
            if let match = visibleTabs.first(where: { $0.id == current.id }) {
                self.currentTab = match
            }
        }
        // After reattaching, ensure gradient matches the restored current space.
        if let space = self.currentSpace {
            bm.syncWorkspaceThemeAcrossWindows(for: space, animate: false)
        }

        // After reattaching BrowserManager, backfill any missing space.profileId
        reconcileSpaceProfilesIfNeeded()
    }
}
