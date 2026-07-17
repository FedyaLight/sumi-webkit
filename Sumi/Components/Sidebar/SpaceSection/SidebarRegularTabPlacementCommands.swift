import Foundation

@MainActor
final class SidebarRegularTabPlacementCommands {
    private let moves: SidebarDragOperationRouter
    private let folderTabPlacement: TabFolderTabPlacementTransaction
    private let profiles: TabProfileTransitionService

    init(
        moves: SidebarDragOperationRouter,
        folderTabPlacement: TabFolderTabPlacementTransaction,
        profiles: TabProfileTransitionService
    ) {
        self.moves = moves
        self.folderTabPlacement = folderTabPlacement
        self.profiles = profiles
    }

    func moveTab(_ tabID: UUID, to targetSpaceID: UUID) {
        moves.moveTab(tabID, to: targetSpaceID)
    }

    func moveTabToFolder(_ tab: Tab, folderID: UUID) {
        folderTabPlacement.moveTabToFolder(tab, folderID: folderID)
    }

    @discardableResult
    func assign(_ tab: Tab, toProfile profileID: UUID) -> Bool {
        profiles.assign(tab, toProfile: profileID)
    }
}
