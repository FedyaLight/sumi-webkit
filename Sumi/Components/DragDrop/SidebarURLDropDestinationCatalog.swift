import Foundation

@MainActor
protocol SidebarURLDropDestinationResolving: AnyObject {
    func space(_ spaceID: UUID) -> Space?
    func folder(_ folderID: UUID) -> (folder: TabFolder, space: Space)?
    func essentialsInsertion(
        in windowState: BrowserWindowState,
        at index: Int
    ) -> EssentialsShortcutPlacementOwner.InsertionPlan?
}

@MainActor
final class SidebarURLDropDestinationCatalog: SidebarURLDropDestinationResolving {
    private let spaces: TabSpaceCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let essentials: EssentialsShortcutPlacementOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        essentials: EssentialsShortcutPlacementOwner
    ) {
        self.spaces = spaces
        self.folders = folders
        self.essentials = essentials
    }

    func space(_ spaceID: UUID) -> Space? {
        spaces.spaces.first { $0.id == spaceID }
    }

    func folder(_ folderID: UUID) -> (folder: TabFolder, space: Space)? {
        guard let folder = folders.folder(by: folderID),
              let spaceID = folders.spaceId(for: folderID),
              let space = space(spaceID)
        else { return nil }
        return (folder, space)
    }

    func essentialsInsertion(
        in windowState: BrowserWindowState,
        at index: Int
    ) -> EssentialsShortcutPlacementOwner.InsertionPlan? {
        essentials.resolveInsertion(
            using: EssentialsShortcutPlacementOwner.InsertionContext(
                target: EssentialsShortcutPlacementOwner.TargetContext(
                    windowState: windowState
                ),
                targetIndex: index
            )
        )
    }
}
