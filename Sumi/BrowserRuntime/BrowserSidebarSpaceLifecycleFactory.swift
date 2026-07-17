import Foundation

@MainActor
enum BrowserSidebarSpaceLifecycleFactory {
    static func make(
        runtime: TabRuntimePortConnection,
        spaces: TabSpaceCollectionStateOwner,
        pins: ShortcutPinCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        splitGroups: SplitGroupStore,
        splitOrdering: SplitGroupSidebarOrderingService,
        regularTabs: RegularTabCollectionOwner,
        catalog: SpaceCatalogCommands,
        removal: SpaceRemovalService
    ) -> SidebarSpaceLifecycle {
        let spaceCatalog = SidebarSpaceCatalogProjection(
            runtime: runtime,
            spaces: spaces,
            pins: pins
        )
        let pinnedInventory = SidebarPinnedInventoryProjection(
            folders: folders,
            pins: pins,
            splitGroups: splitGroups,
            splitOrdering: splitOrdering
        )
        let inventory = SidebarSpaceInventoryProjection(
            runtime: runtime,
            spaces: spaces,
            regularTabs: regularTabs,
            pinned: pinnedInventory
        )
        return SidebarSpaceLifecycle(
            runtimeIsAlive: { [runtime] in runtime.current != nil },
            spaces: spaceCatalog,
            inventory: inventory,
            catalog: catalog,
            removal: removal
        )
    }
}
