import Foundation

@MainActor
protocol SidebarURLDropDestinationResolving: AnyObject {
    func space(_ spaceID: UUID) -> Space?
    func folder(_ folderID: UUID) -> (folder: TabFolder, space: Space)?
    func favoriteInsertion(
        in windowState: BrowserWindowState,
        at index: Int
    ) -> FavoriteShortcutPlacementOwner.InsertionPlan?
}

@MainActor
final class SidebarURLDropDestinationCatalog: SidebarURLDropDestinationResolving {
    private let spaces: TabSpaceCollectionStateOwner
    private let folders: TabFolderCollectionStateOwner
    private let favorite: FavoriteShortcutPlacementOwner

    init(
        spaces: TabSpaceCollectionStateOwner,
        folders: TabFolderCollectionStateOwner,
        favorite: FavoriteShortcutPlacementOwner
    ) {
        self.spaces = spaces
        self.folders = folders
        self.favorite = favorite
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

    func favoriteInsertion(
        in windowState: BrowserWindowState,
        at index: Int
    ) -> FavoriteShortcutPlacementOwner.InsertionPlan? {
        favorite.resolveInsertion(
            using: FavoriteShortcutPlacementOwner.InsertionContext(
                target: FavoriteShortcutPlacementOwner.TargetContext(
                    windowState: windowState
                ),
                targetIndex: index
            )
        )
    }
}
