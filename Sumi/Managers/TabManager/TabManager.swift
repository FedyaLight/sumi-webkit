import AppKit
import Combine
import Observation
import SwiftData
import WebKit
import OSLog

@MainActor
class TabManager: ObservableObject {
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

    lazy var tabRepository = TabRepositoryService(tabManager: self)
    lazy var runtimeStore = DefaultTabRuntimeStore(tabManager: self)
    lazy var mutationService = TabMutationService(tabManager: self)
    lazy var folderService = TabFolderService(tabManager: self)

    // Tab closure undo tracking - stores snapshot of tab state at closure time
    var recentlyClosedTabs: [(tab: Tab, spaceId: UUID?, currentURL: URL?, canGoBack: Bool, canGoForward: Bool, timestamp: Date)] = []
    let undoDuration: TimeInterval = 20.0 // 20 seconds
    var undoTimer: Timer?

    // Toast notification cooldown
    var lastTabClosureTime: Date?
    let toastCooldown: TimeInterval = 2 * 60 * 60 // 2 hours in seconds

    // Spaces
    @Published var spaces: [Space] = []
    @Published var currentSpace: Space?

    // Normal tabs per space
    @Published var tabsBySpace: [UUID: [Tab]] = [:]

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
    private var tabLookup: [UUID: Tab] = [:]
    private var transientTabLookupIDs: Set<UUID> = []
    private var attachedLiveTabIDs: Set<UUID> = []
    /// Emitted when tab structure changes without a corresponding `@Published` update (e.g. transient shortcut live tabs). Not used for snapshot persistence completion—`scheduleStructuralPersistence()` does not send this.
    let structuralChanges = PassthroughSubject<Void, Never>()
    // Space activation to resume after a deferred profile switch
    var pendingSpaceActivation: UUID?
    
    // Live essentials API for shell views that still read a tab-backed collection.
    var pinnedTabs: [Tab] {
        activeEssentialTabs(for: browserManager?.currentProfile?.id)
    }
    
    var essentialTabs: [Tab] { pinnedTabs }
    
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

    func normalizedLauncherLookupURL(_ url: URL) -> String {
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: true) else {
            return url.absoluteString.lowercased()
        }
        components.fragment = nil
        return components.string?.lowercased() ?? url.absoluteString.lowercased()
    }

    func spacePinnedPin(matching url: URL, in spaceId: UUID) -> ShortcutPin? {
        let normalizedURL = normalizedLauncherLookupURL(url)
        return spacePinnedPins(for: spaceId).first { pin in
            normalizedLauncherLookupURL(pin.launchURL) == normalizedURL
        }
    }

    @discardableResult
    func ensureSpacePinnedLauncher(for tab: Tab, in spaceId: UUID) -> ShortcutPin? {
        guard spaces.contains(where: { $0.id == spaceId }) else { return nil }

        if let shortcutId = tab.shortcutPinId,
           let existingPin = shortcutPin(by: shortcutId),
           existingPin.role == .spacePinned {
            existingPin.refreshFromLiveTab(tab)
            return existingPin
        }

        if let existingPin = spacePinnedPin(matching: tab.url, in: spaceId) {
            let trimmedTitle = tab.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let refreshedTitle = trimmedTitle.isEmpty ? existingPin.title : trimmedTitle
            let updatedPin = updateShortcutPin(existingPin, title: refreshedTitle) ?? existingPin
            updatedPin.refreshFromLiveTab(tab)
            return updatedPin
        }

        let targetIndex = topLevelSpacePinnedItems(for: spaceId).count
        let newPin = makeShortcutPin(
            from: tab,
            role: .spacePinned,
            profileId: nil,
            spaceId: spaceId,
            folderId: nil,
            index: targetIndex
        )

        guard let insertedPin = insertShortcutPin(newPin, at: targetIndex) else {
            return nil
        }

        insertedPin.refreshFromLiveTab(tab)
        scheduleStructuralPersistence()
        return insertedPin
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
        self.persistence = TabSnapshotRepository(container: context.container)
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
            pendingRuntimeStatePersistTasks.values.forEach { $0.cancel() }
            pendingRuntimeStatePersistTasks.removeAll()
            tabsBySpace.removeAll()
            spacePinnedShortcuts.removeAll()
            foldersBySpace.removeAll()
            pinnedByProfile.removeAll()
            pendingPinnedWithoutProfile.removeAll()
            transientShortcutTabsByWindow.removeAll()
            tabLookup.removeAll()
            transientTabLookupIDs.removeAll()
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
        return Array(tabsBySpace[s.id] ?? [])
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
        replaceTabLookupEntries(removing: previousTabs, with: sortedItems)
        structuralChanges.send()
    }

    func setFolders(_ items: [TabFolder], for spaceId: UUID) {
        let previousFolders = foldersBySpace[spaceId] ?? []
        foldersBySpace[spaceId] = items
        markFoldersSnapshotDirty(for: spaceId)
        recordFoldersStructuralChange(previous: previousFolders, current: items)
        structuralChanges.send()
    }

    func setPinnedTabs(_ items: [ShortcutPin], for profileId: UUID) {
        let previousPins = pinnedByProfile[profileId] ?? []
        pinnedByProfile[profileId] = items
        markPinnedSnapshotDirty(for: profileId)
        recordShortcutPinsStructuralChange(previous: previousPins, current: items)
        structuralChanges.send()
    }

    func setSpacePinnedShortcuts(_ items: [ShortcutPin], for spaceId: UUID) {
        let previousPins = spacePinnedShortcuts[spaceId] ?? []
        spacePinnedShortcuts[spaceId] = items
        markSpacePinnedSnapshotDirty(for: spaceId)
        recordShortcutPinsStructuralChange(previous: previousPins, current: items)
        structuralChanges.send()
    }

    func notifyTransientShortcutStateChanged() {
        refreshTransientTabLookup()
        structuralChanges.send()
    }

    func tab(for id: UUID) -> Tab? {
        if let tab = tabLookup[id] {
            return tab
        }

        rebuildTabLookup()
        return tabLookup[id]
    }

    private func rebuildTabLookup() {
        var updatedLookup: [UUID: Tab] = [:]
        updatedLookup.reserveCapacity(
            tabsBySpace.values.reduce(0) { $0 + $1.count }
                + transientShortcutTabsByWindow.values.reduce(0) { $0 + $1.count }
        )

        for tabs in tabsBySpace.values {
            for tab in tabs {
                updatedLookup[tab.id] = tab
            }
        }

        for liveTabs in transientShortcutTabsByWindow.values {
            for tab in liveTabs.values {
                updatedLookup[tab.id] = tab
            }
        }

        tabLookup = updatedLookup
        transientTabLookupIDs = Set(
            transientShortcutTabsByWindow.values
                .flatMap(\.values)
                .map(\.id)
        )
    }

    private func replaceTabLookupEntries(removing previousTabs: [Tab], with currentTabs: [Tab]) {
        let currentIDs = Set(currentTabs.map(\.id))
        for tab in previousTabs where !currentIDs.contains(tab.id) {
            tabLookup.removeValue(forKey: tab.id)
        }
        for tab in currentTabs {
            tabLookup[tab.id] = tab
        }
    }

    private func refreshTransientTabLookup() {
        for tabId in transientTabLookupIDs {
            tabLookup.removeValue(forKey: tabId)
        }

        var updatedIDs: Set<UUID> = []
        for liveTabs in transientShortcutTabsByWindow.values {
            for tab in liveTabs.values {
                tabLookup[tab.id] = tab
                updatedIDs.insert(tab.id)
            }
        }

        transientTabLookupIDs = updatedIDs
    }
    func normalizedSpacePinnedShortcuts(_ items: [ShortcutPin], for spaceId: UUID) -> [ShortcutPin] {
        var groupedByFolder = Dictionary(grouping: items) { $0.folderId }

        func normalizedGroup(_ pins: [ShortcutPin]) -> [ShortcutPin] {
            pins
                .sorted { lhs, rhs in
                    if lhs.index != rhs.index { return lhs.index < rhs.index }
                    return lhs.id.uuidString < rhs.id.uuidString
                }
                .enumerated()
                .map { index, pin in pin.refreshed(index: index) }
        }

        var normalized: [ShortcutPin] = []

        let remainingFolderIds = groupedByFolder.keys
            .compactMap { $0 }
            .sorted { $0.uuidString < $1.uuidString }

        for folderId in remainingFolderIds {
            let pins = groupedByFolder.removeValue(forKey: folderId) ?? []
            normalized.append(contentsOf: normalizedGroup(pins))
        }

        let topLevelPins = groupedByFolder.removeValue(forKey: nil) ?? []
        normalized.append(contentsOf: topLevelPins.sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        })

        return normalized
    }

    enum SpacePinnedTopLevelItem {
        case folder(TabFolder)
        case shortcut(ShortcutPin)

        var id: UUID {
            switch self {
            case .folder(let folder): return folder.id
            case .shortcut(let pin): return pin.id
            }
        }
    }

    func topLevelSpacePinnedItems(for spaceId: UUID) -> [SpacePinnedTopLevelItem] {
        let folders = (foldersBySpace[spaceId] ?? []).map { ($0.index, SpacePinnedTopLevelItem.folder($0)) }
        let pins = spacePinnedPins(for: spaceId)
            .filter { $0.folderId == nil }
            .map { ($0.index, SpacePinnedTopLevelItem.shortcut($0)) }
        return (folders + pins)
            .sorted { lhs, rhs in
                if lhs.0 != rhs.0 { return lhs.0 < rhs.0 }
                return lhs.1.id.uuidString < rhs.1.id.uuidString
            }
            .map(\.1)
    }

    func applyTopLevelSpacePinnedOrder(
        _ items: [SpacePinnedTopLevelItem],
        for spaceId: UUID
    ) {
        let folderMap = Dictionary(uniqueKeysWithValues: (foldersBySpace[spaceId] ?? []).map { ($0.id, $0) })
        var orderedFolders: [TabFolder] = []
        var orderedTopLevelPins: [ShortcutPin] = []

        for (index, item) in items.enumerated() {
            switch item {
            case .folder(let folder):
                let target = folderMap[folder.id] ?? folder
                target.index = index
                target.spaceId = spaceId
                orderedFolders.append(target)
            case .shortcut(let pin):
                orderedTopLevelPins.append(pin.refreshed(index: index).moved(toFolderId: nil))
            }
        }

        let remainingFolders = (foldersBySpace[spaceId] ?? [])
            .filter { folder in orderedFolders.contains(where: { $0.id == folder.id }) == false }
        let finalFolders = (orderedFolders + remainingFolders).sorted { lhs, rhs in
            if lhs.index != rhs.index { return lhs.index < rhs.index }
            return lhs.id.uuidString < rhs.id.uuidString
        }
        setFolders(finalFolders, for: spaceId)

        let folderPins = (spacePinnedShortcuts[spaceId] ?? []).filter { $0.folderId != nil }
        let finalPins = normalizedSpacePinnedShortcuts(folderPins + orderedTopLevelPins, for: spaceId)
        setSpacePinnedShortcuts(finalPins, for: spaceId)
    }

    func insertTopLevelSpacePinnedShortcut(
        _ pin: ShortcutPin,
        in spaceId: UUID,
        at targetIndex: Int
    ) -> ShortcutPin? {
        var items = topLevelSpacePinnedItems(for: spaceId)
        let safeIndex = max(0, min(targetIndex, items.count))
        items.insert(.shortcut(pin.moved(toFolderId: nil)), at: safeIndex)
        applyTopLevelSpacePinnedOrder(items, for: spaceId)
        return spacePinnedShortcuts[spaceId]?.first(where: { $0.id == pin.id })
    }

    func reorderTopLevelSpacePinnedShortcut(
        _ pin: ShortcutPin,
        in spaceId: UUID,
        to targetIndex: Int
    ) -> ShortcutPin? {
        var items = topLevelSpacePinnedItems(for: spaceId)
        guard let currentIndex = items.firstIndex(where: {
            if case .shortcut(let existingPin) = $0 { return existingPin.id == pin.id }
            return false
        }) else { return nil }
        guard currentIndex != targetIndex else { return pin }
        let moving = items.remove(at: currentIndex)
        let adjustedIndex = currentIndex < targetIndex ? targetIndex - 1 : targetIndex
        let safeIndex = max(0, min(adjustedIndex, items.count))
        items.insert(moving, at: safeIndex)
        applyTopLevelSpacePinnedOrder(items, for: spaceId)
        return spacePinnedShortcuts[spaceId]?.first(where: { $0.id == pin.id })
    }

    func reorderFolderInTopLevelPinned(
        _ folder: TabFolder,
        in spaceId: UUID,
        to targetIndex: Int
    ) {
        var items = topLevelSpacePinnedItems(for: spaceId)
        guard let currentIndex = items.firstIndex(where: {
            if case .folder(let existingFolder) = $0 { return existingFolder.id == folder.id }
            return false
        }) else { return }
        guard currentIndex != targetIndex else { return }
        let moving = items.remove(at: currentIndex)
        let adjustedIndex = currentIndex < targetIndex ? targetIndex - 1 : targetIndex
        let safeIndex = max(0, min(adjustedIndex, items.count))
        items.insert(moving, at: safeIndex)
        applyTopLevelSpacePinnedOrder(items, for: spaceId)
        scheduleStructuralPersistence()
    }

    func withSpacePinnedShortcutGroup(
        for spaceId: UUID,
        folderId: UUID?,
        _ mutate: (inout [ShortcutPin]) -> Void
    ) {
        let allPins = spacePinnedShortcuts[spaceId] ?? []
        var targetGroup = allPins
            .filter { $0.folderId == folderId }
            .sorted { lhs, rhs in
                if lhs.index != rhs.index { return lhs.index < rhs.index }
                return lhs.id.uuidString < rhs.id.uuidString
            }
        let otherPins = allPins.filter { $0.folderId != folderId }

        mutate(&targetGroup)

        let normalizedGroup = targetGroup.enumerated().map { index, pin in
            pin.refreshed(index: index)
        }
        let rebuilt = normalizedSpacePinnedShortcuts(otherPins + normalizedGroup, for: spaceId)
        setSpacePinnedShortcuts(rebuilt, for: spaceId)
    }

    func attach(_ tab: Tab) {
        tab.browserManager = browserManager
        tab.sumiSettings = sumiSettings
        tabLookup[tab.id] = tab

        attachedLiveTabIDs.insert(tab.id)
    }

    func detach(_ tab: Tab) {
        attachedLiveTabIDs.remove(tab.id)
        tabLookup.removeValue(forKey: tab.id)
    }

    func allTabsAllSpaces() -> [Tab] {
        let normals = spaces.flatMap { tabsBySpace[$0.id] ?? [] }
        return transientShortcutTabsByWindow.values.flatMap(\.values) + normals
    }

    // Public accessor for managers that need to iterate tabs (e.g., privacy, rules updates)
    func allTabs() -> [Tab] {
        if tabLookup.isEmpty {
            rebuildTabLookup()
        }

        let normals = spaces.flatMap { tabsBySpace[$0.id] ?? [] }
        return transientShortcutTabsByWindow.values.flatMap(\.values) + normals
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
        let regular = spaces
            .filter { spaceIds.contains($0.id) }
            .flatMap { tabsBySpace[$0.id] ?? [] }
        return pinned + spacePinned + regular
    }

    func hasSpacePinnedContent(for spaceId: UUID) -> Bool {
        !spacePinnedPins(for: spaceId).isEmpty
            || !(foldersBySpace[spaceId] ?? []).isEmpty
    }

    private func contains(_ tab: Tab) -> Bool {
        if activeShortcutTabs().contains(where: { $0.id == tab.id }) {
            return true
        }
        if allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) {
            return true
        }
        if let sid = tab.spaceId,
           (tabsBySpace[sid] ?? []).contains(where: { $0.id == tab.id }) {
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

    /// True if the tab is a regular (non-pinned) tab in its space.
    func isRegular(_ tab: Tab) -> Bool {
        guard let sid = tab.spaceId, let arr = tabsBySpace[sid] else { return false }
        return arr.contains { $0.id == tab.id }
    }

    /// Create a new regular tab duplicating the source tab's URL/name and insert near an anchor tab.
    /// - Parameters:
    ///   - source: The tab to duplicate (pinned/space-pinned or regular).
    ///   - anchor: A regular tab used to decide target space and placement. If nil, falls back to currentSpace.
    ///   - placeAfterAnchor: If true, insert right after the anchor's index; otherwise at the anchor's index.
    /// - Returns: The newly created regular Tab.
    @discardableResult
    func duplicateAsRegularForSplit(from source: Tab, anchor: Tab?, placeAfterAnchor: Bool = true) -> Tab {
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

        // Add at end first, then reposition next to anchor if provided.
        addTab(newTab)

        if let a = anchor, let sid = a.spaceId, let arr = tabsBySpace[sid] {
            // Find indices in current ordering
            if let anchorIndex = arr.firstIndex(where: { $0.id == a.id }),
               let newIndex = arr.firstIndex(where: { $0.id == newTab.id })
            {
                // Compute desired position relative to anchor
                let desired = min(max(anchorIndex + (placeAfterAnchor ? 1 : 0), 0), arr.count)
                if newIndex != desired {
                    reorderRegularTabs(newTab, in: sid, to: desired)
                }
            }
        }

        return newTab
    }

    // MARK: - Folder Management

    func createFolder(for spaceId: UUID, name: String = "New Folder") -> TabFolder {
        folderService.createFolder(for: spaceId, name: name)
    }

    func renameFolder(_ folderId: UUID, newName: String) {
        folderService.renameFolder(folderId, newName: newName)
    }

    func updateFolderIcon(_ folderId: UUID, icon: String) {
        folderService.updateFolderIcon(folderId, icon: icon)
    }

    func deleteFolder(_ folderId: UUID) {
        folderService.deleteFolder(folderId)
    }

    func folders(for spaceId: UUID) -> [TabFolder] {
        folderService.folders(for: spaceId)
    }

    func toggleFolder(_ folderId: UUID) {
        folderService.toggleFolder(folderId)
    }

    func openFolderIfNeeded(_ folderId: UUID) {
        for (_, folders) in foldersBySpace {
            if let folder = folders.first(where: { $0.id == folderId }) {
                if !folder.isOpen {
                    folder.isOpen = true
                    markFoldersStructurallyDirty(for: folder.spaceId)
                }
                return
            }
        }
    }

    func revealFolderForDrag(_ folderId: UUID) {
        folderService.revealFolderForDrag(folderId)
    }

    func setAllFolders(open isOpen: Bool, in spaceId: UUID) {
        folderService.setAllFolders(open: isOpen, in: spaceId)
    }

    func moveTabToFolder(tab: Tab, folderId: UUID) {
        folderService.moveTabToFolder(tab: tab, folderId: folderId)
    }

    // MARK: - Tab Management (Normal within current space)

    func addTab(_ tab: Tab) {
        attach(tab)
        if contains(tab) { return }

        if tab.spaceId == nil {
            tab.spaceId = currentSpace?.id
        }
        guard let sid = tab.spaceId else {
            RuntimeDiagnostics.debug("Skipping addTab for '\(tab.name)' because no spaceId was resolved.", category: "TabManager")
            return
        }
        var arr = tabsBySpace[sid] ?? []
        arr.append(tab)
        setTabs(arr, for: sid)
        
        // Load the tab in compositor if it's the current tab
        if tab.id == currentTab?.id {
            browserManager?.compositorManager.loadTab(tab)
        }
        
        RuntimeDiagnostics.debug("Added regular tab '\(tab.name)' to space \(sid.uuidString).", category: "TabManager")
        scheduleStructuralPersistence()
    }

    func removeTab(_ id: UUID) {
        // Notify SplitViewManager about tab closure to prevent zombie state
        browserManager?.splitManager.handleTabClosure(id)
        cancelRuntimeStatePersistence(for: id)
        
        let wasCurrent = (currentTab?.id == id)
        var removed: Tab?
        var removedSpaceId: UUID?
        var removedIndexInCurrentSpace: Int?

        if removed == nil {
            for space in spaces {
                // Then check regular tabs
                if var arr = tabsBySpace[space.id],
                   let i = arr.firstIndex(where: { $0.id == id })
                {
                    if i < arr.count { removed = arr.remove(at: i) }
                    removedSpaceId = space.id
                    removedIndexInCurrentSpace =
                        (space.id == currentSpace?.id) ? i : nil
                    setTabs(arr, for: space.id)
                    break
                }
            }
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

        browserManager?.extensionManager.notifyTabClosed(tab)

        browserManager?.windowRegistry?.windows.values.forEach { windowState in
            windowState.removeFromRegularTabHistory(tab.id)
        }

        // Add to recently closed tabs for undo functionality
        trackRecentlyClosedTab(tab, spaceId: removedSpaceId)

        // Force unload the tab from compositor before removing
        browserManager?.compositorManager.unloadTab(tab)
        browserManager?.webViewCoordinator?.removeAllWebViews(for: tab)
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
                    let arr = tabsBySpace[cs.id] ?? []
                    currentTab = spacePinned.last ?? arr.last
                } else {
                    currentTab = nil
                }
            } else if let cs = currentSpace {
                // Tab was in a space
                let spacePinned = liveSpacePinnedTabs(for: cs.id)
                let arr = tabsBySpace[cs.id] ?? []
                
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

    func setActiveTab(_ tab: Tab) {
        guard contains(tab) else {
            return
        }
        let previous = currentTab
        if previous?.id != tab.id {
            currentTab = tab
        }

        // Do not auto-exit split when leaving split panes; preserve split state

        // Update active side in split view for all windows that contain this tab
        // Also update windowState.currentTabId for windows that have this tab in split view
        if let bm = browserManager {
            for (windowId, windowState) in bm.windowRegistry?.windows ?? [:] {
                // Check if this tab is in split view for this window
                if bm.splitManager.isSplit(for: windowId) {
                    let state = bm.splitManager.getSplitState(for: windowId)
                    // If tab is on left or right side, update active side and window's current tab
                    if state.leftTabId == tab.id || state.rightTabId == tab.id {
                        bm.splitManager.updateActiveSide(for: tab.id, in: windowId)
                        // Update window's current tab ID so other UI components work correctly
                        if windowState.currentTabId != tab.id {
                            windowState.currentTabId = tab.id
                        }
                    }
                }
            }
        }

        // Save this tab as the active tab for the appropriate space
        var didChangeSpacePersistenceState = false
        if let sid = tab.spaceId, let space = spaces.first(where: { $0.id == sid }) {
            if space.activeTabId != tab.id {
                space.activeTabId = tab.id
                didChangeSpacePersistenceState = true
            }
            if currentSpace?.id != space.id {
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

        if previous?.id != tab.id {
            browserManager?.extensionManager.notifyTabActivated(
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
        
        // Save this tab as the active tab for the appropriate space
        var didChangeSpacePersistenceState = false
        if let sid = tab.spaceId, let space = spaces.first(where: { $0.id == sid }) {
            if space.activeTabId != tab.id {
                space.activeTabId = tab.id
                didChangeSpacePersistenceState = true
            }
            currentSpace = space
        } else if let cs = currentSpace {
            if cs.activeTabId != tab.id {
                cs.activeTabId = tab.id
                didChangeSpacePersistenceState = true
            }
        }
        if didChangeSpacePersistenceState {
            markSpacesSnapshotDirty()
        }
        
        persistSelection()
    }

    @discardableResult
    func createNewTab(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil
    ) -> Tab {
        let settings = sumiSettings ?? browserManager?.sumiSettings
        let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        let normalizedUrl = normalizeURL(url, queryTemplate: template)
        guard let validURL = URL(string: normalizedUrl)
        else {
            RuntimeDiagnostics.debug("Invalid URL '\(url)' while creating a new tab; falling back to Sumi empty surface.", category: "TabManager")
            return createNewTab(in: space)
        }

        let targetSpace: Space? = space ?? currentSpace ?? ensureDefaultSpaceIfNeeded()
        // Ensure the target space has a profile assignment; backfill from currentProfile if missing
        if let ts = targetSpace, ts.profileId == nil {
            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let pid = defaultProfileId {
                ts.profileId = pid
                markAllSpacesStructurallyDirty()
                scheduleStructuralPersistence()
            }
        }
        let sid = targetSpace?.id

        let nextIndex = sid
            .flatMap { tabsBySpace[$0]?.map(\.index).max() }
            .map { $0 + 1 }
            ?? 0

        let newTab = Tab(
            url: validURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: sid,
            index: nextIndex,
            browserManager: browserManager
        )
        newTab.profileId = targetSpace?.profileId
        if let webViewConfigurationOverride {
            newTab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
        }
        addTab(newTab)
        if activate {
            setActiveTab(newTab)
        }
        return newTab
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
        let newTab = Tab(
            url: url,
            name: url.host ?? "New Tab",
            favicon: "globe",
            spaceId: nil,
            index: 0,
            browserManager: browserManager
        )
        newTab.profileId = profile.id
        
        // Add to window's ephemeral tabs (NOT to persistent tabs)
        windowState.ephemeralTabs.append(newTab)
        windowState.currentTabId = newTab.id
        
        RuntimeDiagnostics.emit("🔒 [TabManager] Created ephemeral tab: \(newTab.id) in window: \(windowState.id)")
        
        return newTab
    }

    // Create a new tab with an existing WebView (used for Peek transfers)
    @discardableResult
    func createNewTabWithWebView(
        url: String = SumiSurface.emptyTabURL.absoluteString,
        in space: Space? = nil,
        existingWebView: WKWebView? = nil
    ) -> Tab {
        let settings = sumiSettings ?? browserManager?.sumiSettings
        let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        let normalizedUrl = normalizeURL(url, queryTemplate: template)
        guard let validURL = URL(string: normalizedUrl)
        else {
            RuntimeDiagnostics.debug("Invalid URL '\(url)' while creating a WebView-backed tab; falling back to Sumi empty surface.", category: "TabManager")
            return createNewTab(in: space)
        }

        let targetSpace: Space? = space ?? currentSpace ?? ensureDefaultSpaceIfNeeded()
        // Ensure the target space has a profile assignment; backfill from currentProfile if missing
        if let ts = targetSpace, ts.profileId == nil {
            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let pid = defaultProfileId {
                ts.profileId = pid
                markAllSpacesStructurallyDirty()
                scheduleStructuralPersistence()
            }
        }
        let sid = targetSpace?.id

        let nextIndex = sid
            .flatMap { tabsBySpace[$0]?.map(\.index).max() }
            .map { $0 + 1 }
            ?? 0

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

    // Create a new blank tab intended to host a popup window. The returned tab's
    // WKWebView is returned to WebKit so it can load popup content. No initial
    // navigation is performed to preserve window.opener scripting semantics.
    @discardableResult
    func createPopupTab(
        in space: Space? = nil,
        activate: Bool = true,
        webViewConfigurationOverride: WKWebViewConfiguration? = nil
    ) -> Tab {
        let targetSpace: Space? = space ?? currentSpace ?? ensureDefaultSpaceIfNeeded()
        // Ensure target space has a profile assignment
        if let ts = targetSpace, ts.profileId == nil {
            let defaultProfileId = browserManager?.currentProfile?.id ?? browserManager?.profileManager.profiles.first?.id
            if let pid = defaultProfileId {
                ts.profileId = pid
                markAllSpacesStructurallyDirty()
                scheduleStructuralPersistence()
            }
        }
        let sid = targetSpace?.id
        let existingTabs = sid.flatMap { tabsBySpace[$0] } ?? []
        let nextIndex = (existingTabs.map { $0.index }.max() ?? -1) + 1

        guard let blankURL = URL(string: "about:blank") else {
            preconditionFailure("TabManager: invalid about:blank URL")
        }
        let newTab = Tab(
            url: blankURL,
            name: "New Tab",
            favicon: "globe",
            spaceId: sid,
            index: nextIndex,
            browserManager: browserManager
        )
        newTab.isPopupHost = true
        if let webViewConfigurationOverride {
            newTab.applyWebViewConfigurationOverride(webViewConfigurationOverride)
        }
        addTab(newTab)
        if activate {
            setActiveTab(newTab)
        }
        return newTab
    }

    // Ensure a default space exists and is active; create a Personal space if needed
    private func ensureDefaultSpaceIfNeeded() -> Space {
        if let cs = currentSpace { return cs }
        if spaces.isEmpty {
            let resolvedProfileId = browserManager?.currentProfile?.id
            let personal = Space(
                name: "Personal",
                icon: "person.crop.circle",
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

    func closeActiveTab() {
        guard let currentTab else {
            RuntimeDiagnostics.emit("No active tab to close")
            return
        }
        removeTab(currentTab.id)
    }

    func clearRegularTabs(for spaceId: UUID) {
        guard let tabs = tabsBySpace[spaceId] else { return }

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
    
    func unloadTab(_ tab: Tab) {
        // Never unload essentials tabs except on browser close/restart
        guard !allPinnedTabsAllProfiles.contains(where: { $0.id == tab.id }) else { return }
        browserManager?.compositorManager.unloadTab(tab)
    }
    
    func unloadAllInactiveTabs() {
        // Only unload regular tabs, never essentials (pinned) tabs
        for tab in tabs {
            if tab.id != currentTab?.id {
                unloadTab(tab)
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
    var pendingRuntimeStatePersistTasks: [UUID: Task<Void, Never>] = [:]
    let runtimeStatePersistDebounceNanoseconds: UInt64 = 250_000_000
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
