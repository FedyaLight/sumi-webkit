import Foundation
import SumiDomain

@MainActor
protocol SidebarRegularTabsControlling {
    var spaces: [Space] { get }

    func tabs(in space: Space, windowState: BrowserWindowState) -> [Tab]
    func hasPersistedTabs(in space: Space) -> Bool
    func tab(for id: UUID) -> Tab?
    func splitGroup(containing memberID: SplitMemberID) -> SplitGroup?
    func shortcutPin(by id: UUID) -> ShortcutPin?
    func userFolders(for spaceId: UUID) -> [TabFolder]
    func canAddToEssentials(_ tab: Tab, in space: Space, windowState: BrowserWindowState) -> Bool
    func clearRegularTabs(for spaceId: UUID)
    func pinTabToSpace(_ tab: Tab, spaceId: UUID)
    func addTabToEssentials(_ tab: Tab, in space: Space, windowState: BrowserWindowState)
    func closeAllTabsBelow(_ tab: Tab)
    func moveTab(_ tabId: UUID, to targetSpaceId: UUID)
    func moveTabToFolder(_ tab: Tab, folderId: UUID)
    @discardableResult
    func assign(_ tab: Tab, toProfile profileId: UUID) -> Bool
}

@MainActor
struct SidebarRegularTabsController: SidebarRegularTabsControlling {
    struct Dependencies {
        let spaces: @MainActor () -> [Space]
        let tabs: @MainActor (Space) -> [Tab]
        let tab: @MainActor (UUID) -> Tab?
        let splitGroup: @MainActor (SplitMemberID) -> SplitGroup?
        let shortcutPin: @MainActor (UUID) -> ShortcutPin?
        let folders: @MainActor (UUID) -> [TabFolder]
        let isLiveFolder: @MainActor (UUID) -> Bool
        let canAddURLToEssentials: @MainActor (URL, EssentialsShortcutPlacementOwner.TargetContext) -> Bool
        let clearRegularTabs: @MainActor (UUID) -> Void
        let pinTabToSpace: @MainActor (Tab, UUID) -> Void
        let pinTabToEssentials: @MainActor (Tab, EssentialsShortcutPlacementOwner.TargetContext) -> Void
        let closeAllTabsBelow: @MainActor (Tab) -> Void
        let moveTab: @MainActor (UUID, UUID) -> Void
        let moveTabToFolder: @MainActor (Tab, UUID) -> Void
        let assignTabToProfile: @MainActor (Tab, UUID) -> Bool
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var spaces: [Space] {
        dependencies.spaces()
    }

    func tabs(in space: Space, windowState: BrowserWindowState) -> [Tab] {
        if windowState.isIncognito {
            return windowState.ephemeralTabs.sorted { $0.index < $1.index }
        }
        return dependencies.tabs(space)
    }

    func hasPersistedTabs(in space: Space) -> Bool {
        !dependencies.tabs(space).isEmpty
    }

    func tab(for id: UUID) -> Tab? {
        dependencies.tab(id)
    }

    func splitGroup(containing memberID: SplitMemberID) -> SplitGroup? {
        dependencies.splitGroup(memberID)
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        dependencies.shortcutPin(id)
    }

    func userFolders(for spaceId: UUID) -> [TabFolder] {
        dependencies.folders(spaceId)
            .filter { dependencies.isLiveFolder($0.id) == false }
    }

    func canAddToEssentials(_ tab: Tab, in space: Space, windowState: BrowserWindowState) -> Bool {
        guard !tab.isPinned && !tab.isSpacePinned else { return false }
        return dependencies.canAddURLToEssentials(
            tab.url,
            EssentialsShortcutPlacementOwner.TargetContext(windowState: windowState, spaceId: space.id)
        )
    }

    func clearRegularTabs(for spaceId: UUID) {
        dependencies.clearRegularTabs(spaceId)
    }

    func pinTabToSpace(_ tab: Tab, spaceId: UUID) {
        dependencies.pinTabToSpace(tab, spaceId)
    }

    func addTabToEssentials(_ tab: Tab, in space: Space, windowState: BrowserWindowState) {
        dependencies.pinTabToEssentials(
            tab,
            EssentialsShortcutPlacementOwner.TargetContext(windowState: windowState, spaceId: space.id)
        )
    }

    func closeAllTabsBelow(_ tab: Tab) {
        dependencies.closeAllTabsBelow(tab)
    }

    func moveTab(_ tabId: UUID, to targetSpaceId: UUID) {
        dependencies.moveTab(tabId, targetSpaceId)
    }

    func moveTabToFolder(_ tab: Tab, folderId: UUID) {
        dependencies.moveTabToFolder(tab, folderId)
    }

    @discardableResult
    func assign(_ tab: Tab, toProfile profileId: UUID) -> Bool {
        dependencies.assignTabToProfile(tab, profileId)
    }
}
