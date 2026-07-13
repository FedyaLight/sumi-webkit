@testable import Sumi
import Foundation

@MainActor
struct SidebarConsumerTestRoles {
    let inventory: SidebarInventoryProjection
    let selection: SidebarWindowSelectionQuery
    let pinProjection: SidebarPinFolderProjection
    let pinCommands: SidebarPinFolderCommands
    let lifecycle: SidebarSpaceLifecycle
}

@MainActor
enum SidebarConsumerTestSupport {
    static func roles(
        tabManager: TabManager,
        windowState: BrowserWindowState? = nil,
        runtimeIsAlive: @escaping @MainActor () -> Bool = { true }
    ) -> SidebarConsumerTestRoles {
        let registry = WindowRegistry()
        if let windowState {
            registry.register(windowState)
        }
        let windows = SidebarWindowIdentityQuery(registry: { registry })
        let inventory = SidebarInventoryProjection(
            runtimeIsAlive: runtimeIsAlive,
            spaces: tabManager.spaceStateOwner,
            regularTabs: tabManager.regularTabCollectionStateOwner,
            folders: tabManager.folderCollectionStateOwner,
            pins: tabManager.shortcutPinCollectionStateOwner,
            splitGroups: tabManager.splitGroupStore,
            splitOrdering: tabManager.splitGroupSidebarOrdering
        )
        let splitQuery = WindowSplitQuery(
            tabManager: { tabManager },
            windowState: { registry.windows[$0] },
            previewIsActive: { _ in false }
        )
        let selection = SidebarWindowSelectionQuery(
            runtimeIsAlive: runtimeIsAlive,
            windows: windows,
            windowTabs: BrowserWindowTabContext(
                selectionService: { nil },
                tabStore: { nil },
                windows: { Array(registry.windows.values) },
                liveShortcutTabs: { windowID in
                    tabManager.liveShortcutTabs.entries(in: windowID).map(\.tab)
                },
                visibleSplitTabIds: { windowID in
                    Set(splitQuery.visibleTabIDs(in: windowID))
                }
            ),
            shortcutPresentation: tabManager.shortcutPresentationOwner,
            splitQuery: splitQuery
        )
        let pinProjection = SidebarPinFolderProjection(
            runtimeIsAlive: runtimeIsAlive,
            windows: windows,
            essentials: tabManager.essentialsShortcutPlacementOwner,
            resolution: tabManager.shortcutPinRuntimeResolutionOwner
        )

        return SidebarConsumerTestRoles(
            inventory: inventory,
            selection: selection,
            pinProjection: pinProjection,
            pinCommands: SidebarPinFolderCommands(
                runtimeIsAlive: runtimeIsAlive,
                windows: windows,
                pins: tabManager.shortcutPinCollectionStateOwner,
                folders: tabManager.folderCollectionStateOwner,
                structure: tabManager.spacePinnedStructureOwner,
                shortcutCommands: tabManager.shortcutPinCommandOwner,
                folderCommands: tabManager.folderMutationOwner,
                materializer: tabManager.shortcutTabMaterializer,
                profileAssignments: tabManager.profileAssignments.shortcuts
            ),
            lifecycle: SidebarSpaceLifecycle(
                runtimeIsAlive: runtimeIsAlive,
                inventory: inventory,
                catalog: tabManager.spaceServices.catalog,
                removal: tabManager.spaceServices.removal
            )
        )
    }
}
