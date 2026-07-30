import Foundation
import SumiDomain

@MainActor
final class ShortcutPinMoveTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let preparer: ShortcutPinMovePreparer
    private let liveFolders: ShortcutLiveFolderPlacementReconciler
    private let committer: ShortcutPinMoveCommitter

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        preparer: ShortcutPinMovePreparer,
        liveFolders: ShortcutLiveFolderPlacementReconciler,
        committer: ShortcutPinMoveCommitter
    ) {
        self.structuralLookup = structuralLookup
        self.preparer = preparer
        self.liveFolders = liveFolders
        self.committer = committer
    }

    func move(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool
    ) -> ShortcutPin? {
        structuralLookup.withTransaction {
            let liveFolderSource = liveFolders.source(for: pin)
            guard let admission = preparer.prepare(
                pin,
                role: role,
                profileID: profileId,
                spaceID: spaceId,
                folderID: folderId,
                index: index
            ) else { return nil }
            let inserted = committer.commit(
                pin,
                to: ShortcutPinMoveCommitter.Destination(
                    role: role,
                    profileID: profileId,
                    spaceID: spaceId,
                    folderID: folderId,
                    index: index,
                    opensFolder: openTargetFolder
                ),
                admission: admission
            )
            if let inserted {
                liveFolders.reconcileMove(inserted, from: liveFolderSource)
            }
            return inserted
        }
    }
}
