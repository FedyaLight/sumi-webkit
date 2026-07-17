import Foundation

@MainActor
extension BrowserManager {
    func composeSidebarRegularTabCatalog() -> SidebarRegularTabCatalog {
        SidebarRegularTabCatalog(
            spaces: spaceStateOwner,
            regularTabs: regularTabCollectionOwner,
            membership: tabCollectionMembershipOwner
        )
    }

    func composeSidebarRegularTabTargetQuery() -> SidebarRegularTabTargetQuery {
        SidebarRegularTabTargetQuery(
            splitGroups: splitGroupStore,
            pins: shortcutPinCollectionStateOwner,
            folders: folderCollectionStateOwner,
            liveFolders: liveFolderManager,
            essentials: essentialsShortcutPlacementOwner
        )
    }

    func composeSidebarRegularTabLifecycleCommands()
        -> SidebarRegularTabLifecycleCommands {
        sidebarRegularTabLifecycleCommands
    }

    func composeSidebarRegularTabShortcutCommands()
        -> SidebarRegularTabShortcutCommands {
        sidebarRegularTabShortcutCommands
    }

    func composeSidebarRegularTabPlacementCommands()
        -> SidebarRegularTabPlacementCommands {
        sidebarRegularTabPlacementCommands
    }
}
