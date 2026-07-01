import Foundation

@MainActor
protocol SidebarRegularTabsControlling {
    var spaces: [Space] { get }

    func tabs(in space: Space, windowState: BrowserWindowState) -> [Tab]
    func hasPersistedTabs(in space: Space) -> Bool
    func tab(for id: UUID) -> Tab?
    func splitGroup(containing tabId: UUID) -> SplitGroup?
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
        let splitGroup: @MainActor (UUID) -> SplitGroup?
        let shortcutPin: @MainActor (UUID) -> ShortcutPin?
        let folders: @MainActor (UUID) -> [TabFolder]
        let isLiveFolder: @MainActor (UUID) -> Bool
        let canAddURLToEssentials: @MainActor (URL, TabManager.EssentialsTargetContext) -> Bool
        let clearRegularTabs: @MainActor (UUID) -> Void
        let pinTabToSpace: @MainActor (Tab, UUID) -> Void
        let pinTabToEssentials: @MainActor (Tab, TabManager.EssentialsTargetContext) -> Void
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

    func splitGroup(containing tabId: UUID) -> SplitGroup? {
        dependencies.splitGroup(tabId)
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
            TabManager.EssentialsTargetContext(windowState: windowState, spaceId: space.id)
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
            TabManager.EssentialsTargetContext(windowState: windowState, spaceId: space.id)
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

extension SidebarRegularTabsController {
    static func live(
        tabManager: TabManager,
        liveFolderManager: SumiLiveFolderManager
    ) -> SidebarRegularTabsController {
        SidebarRegularTabsController(
            dependencies: .live(
                tabManager: tabManager,
                liveFolderManager: liveFolderManager
            )
        )
    }
}

extension SidebarRegularTabsController.Dependencies {
    static func live(
        tabManager: TabManager,
        liveFolderManager: SumiLiveFolderManager
    ) -> Self {
        Self(
            spaces: { [weak tabManager] in
                tabManager?.spaces ?? []
            },
            tabs: { [weak tabManager] space in
                tabManager?.tabs(in: space) ?? []
            },
            tab: { [weak tabManager] id in
                tabManager?.tab(for: id)
            },
            splitGroup: { [weak tabManager] tabId in
                tabManager?.splitGroup(containing: tabId)
            },
            shortcutPin: { [weak tabManager] id in
                tabManager?.shortcutPin(by: id)
            },
            folders: { [weak tabManager] spaceId in
                tabManager?.folders(for: spaceId) ?? []
            },
            isLiveFolder: { [weak liveFolderManager] folderId in
                liveFolderManager?.isLiveFolder(folderId) ?? false
            },
            canAddURLToEssentials: { [weak tabManager] url, context in
                tabManager?.canAddURLToEssentials(url, using: context) ?? false
            },
            clearRegularTabs: { [weak tabManager] spaceId in
                tabManager?.clearRegularTabs(for: spaceId)
            },
            pinTabToSpace: { [weak tabManager] tab, spaceId in
                tabManager?.pinTabToSpace(tab, spaceId: spaceId)
            },
            pinTabToEssentials: { [weak tabManager] tab, context in
                tabManager?.pinTab(tab, context: context)
            },
            closeAllTabsBelow: { [weak tabManager] tab in
                tabManager?.closeAllTabsBelow(tab)
            },
            moveTab: { [weak tabManager] tabId, targetSpaceId in
                tabManager?.moveTab(tabId, to: targetSpaceId)
            },
            moveTabToFolder: { [weak tabManager] tab, folderId in
                tabManager?.moveTabToFolder(tab: tab, folderId: folderId)
            },
            assignTabToProfile: { [weak tabManager] tab, profileId in
                tabManager?.assign(tab: tab, toProfile: profileId) ?? false
            }
        )
    }
}
