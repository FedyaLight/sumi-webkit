import AppKit
import Foundation

@MainActor
final class TabFolderPlacementTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let admission: TabFolderPlacementAdmission
    private let commitTransaction: TabFolderPlacementCommitTransaction

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        admission: TabFolderPlacementAdmission,
        commitTransaction: TabFolderPlacementCommitTransaction
    ) {
        self.structuralLookup = structuralLookup
        self.admission = admission
        self.commitTransaction = commitTransaction
    }

    func handleFolderDragOperation(
        _ folder: TabFolder,
        operation: DragOperation
    ) -> Bool {
        structuralLookup.withTransaction {
            guard let intent = admission.intent(
                folder,
                operation: operation
            ) else { return false }
            return commitTransaction.commit(folder, intent: intent)
        }
    }

    func moveFolder(
        _ folder: TabFolder,
        toParentFolderID parentFolderID: UUID?,
        in spaceID: UUID,
        to targetIndex: Int
    ) -> Bool {
        structuralLookup.withTransaction {
            guard let intent = admission.moveIntent(
                folder,
                toParentFolderID: parentFolderID,
                in: spaceID,
                targetIndex: targetIndex
            ) else { return false }
            return commitTransaction.commit(folder, intent: intent)
        }
    }
}
