import AppKit
import Foundation

@MainActor
final class TabFolderPlacementCommitTransaction {
    private let spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction
    private let folderOpenState: TabFolderOpenStateService

    init(
        spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction,
        folderOpenState: TabFolderOpenStateService
    ) {
        self.spacePinnedVisualOrder = spacePinnedVisualOrder
        self.folderOpenState = folderOpenState
    }

    func commit(
        _ folder: TabFolder,
        intent: TabFolderPlacementIntent
    ) -> Bool {
        switch intent {
        case .reorderTopLevel(let spaceID, let targetIndex):
            return spacePinnedVisualOrder.reorder(
                .folder(folder.id),
                in: spaceID,
                to: targetIndex
            )

        case .move(let parentFolderID, let spaceID, let targetIndex):
            return moveFolder(
                folder,
                toParentFolderID: parentFolderID,
                in: spaceID,
                targetIndex: targetIndex
            )
        }
    }

    private func moveFolder(
        _ folder: TabFolder,
        toParentFolderID parentFolderID: UUID?,
        in spaceID: UUID,
        targetIndex: Int
    ) -> Bool {
        let didMove = spacePinnedVisualOrder.moveFolder(
            folder.id,
            in: spaceID,
            from: folder.parentFolderId,
            to: parentFolderID,
            at: targetIndex
        )
        guard didMove else { return false }
        if let parentFolderID {
            folderOpenState.openFolderIfNeeded(parentFolderID)
        }
        return true
    }
}
