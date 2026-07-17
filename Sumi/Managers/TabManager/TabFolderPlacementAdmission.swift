import AppKit
import Foundation

@MainActor
final class TabFolderPlacementAdmission {
    private let folders: TabFolderCollectionStateOwner
    private let hierarchy: TabFolderHierarchyMutationService
    private let runtimeConnection: TabRuntimePortConnection

    init(
        folders: TabFolderCollectionStateOwner,
        hierarchy: TabFolderHierarchyMutationService,
        runtimeConnection: TabRuntimePortConnection
    ) {
        self.folders = folders
        self.hierarchy = hierarchy
        self.runtimeConnection = runtimeConnection
    }

    func intent(
        _ folder: TabFolder,
        operation: DragOperation
    ) -> TabFolderPlacementIntent? {
        guard folders.folder(by: folder.id) === folder else { return nil }
        switch (operation.fromContainer, operation.toContainer) {
        case (.spacePinned(let sourceSpaceID), .spacePinned(let targetSpaceID))
            where sourceSpaceID == targetSpaceID
                && targetSpaceID == folder.spaceId:
            return .reorderTopLevel(
                spaceID: targetSpaceID,
                targetIndex: operation.toIndex
            )

        case (.spacePinned(let sourceSpaceID), .folder(let targetFolderID))
            where sourceSpaceID == folder.spaceId:
            return moveIntent(
                folder,
                toParentFolderID: targetFolderID,
                in: folder.spaceId,
                targetIndex: operation.toIndex
            )

        case (.folder(let sourceParentID), .spacePinned(let targetSpaceID))
            where targetSpaceID == folder.spaceId:
            guard folder.parentFolderId == sourceParentID else { return nil }
            return moveIntent(
                folder,
                toParentFolderID: nil,
                in: targetSpaceID,
                targetIndex: operation.toIndex
            )

        case (.folder(let sourceParentID), .folder(let targetFolderID)):
            guard folder.parentFolderId == sourceParentID else { return nil }
            return moveIntent(
                folder,
                toParentFolderID: targetFolderID,
                in: folder.spaceId,
                targetIndex: operation.toIndex
            )

        default:
            return nil
        }
    }

    func moveIntent(
        _ folder: TabFolder,
        toParentFolderID parentFolderID: UUID?,
        in spaceID: UUID,
        targetIndex: Int
    ) -> TabFolderPlacementIntent? {
        guard folders.folder(by: folder.id) === folder else { return nil }
        if let parentFolderID {
            guard folders.spaceId(for: parentFolderID) == spaceID,
                  runtimeConnection.current?.isLiveFolder(parentFolderID)
                    != true else {
                return nil
            }
        }
        guard folder.spaceId == spaceID,
              parentFolderID != folder.id,
              hierarchy.isFolder(
                  parentFolderID,
                  descendantOf: folder.id,
                  in: spaceID
              ) == false else {
            return nil
        }
        return .move(
            parentFolderID: parentFolderID,
            spaceID: spaceID,
            targetIndex: targetIndex
        )
    }
}
