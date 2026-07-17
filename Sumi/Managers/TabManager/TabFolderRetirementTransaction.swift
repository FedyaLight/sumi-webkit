import AppKit
import Foundation

@MainActor
final class TabFolderRetirementTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let deletionPreparation: TabFolderDeletionPreparationService
    private let deletionCommit: TabFolderDeletionCommitTransaction
    private let ungroupPreparation: TabFolderUngroupPreparationService
    private let ungroupCommit: TabFolderUngroupCommitTransaction

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        deletionPreparation: TabFolderDeletionPreparationService,
        deletionCommit: TabFolderDeletionCommitTransaction,
        ungroupPreparation: TabFolderUngroupPreparationService,
        ungroupCommit: TabFolderUngroupCommitTransaction
    ) {
        self.structuralLookup = structuralLookup
        self.deletionPreparation = deletionPreparation
        self.deletionCommit = deletionCommit
        self.ungroupPreparation = ungroupPreparation
        self.ungroupCommit = ungroupCommit
    }

    func deleteFolder(_ folderID: UUID) {
        structuralLookup.withTransaction {
            guard let prepared = deletionPreparation.prepare(
                folderID: folderID
            ) else { return }
            _ = deletionCommit.commit(prepared)
        }
    }

    func ungroupFolder(_ folderID: UUID) {
        structuralLookup.withTransaction {
            guard let prepared = ungroupPreparation.prepare(
                folderID: folderID
            ) else { return }
            ungroupCommit.commit(prepared)
        }
    }
}
