import Foundation
import SumiDomain

@MainActor
final class ShortcutPinMoveCommitter {
    struct Destination {
        let role: ShortcutPinRole
        let profileID: UUID?
        let spaceID: UUID?
        let folderID: UUID?
        let index: Int
        let opensFolder: Bool
    }

    private let store: ShortcutPinStoreOwner
    private let bindings: ShortcutTabBindingSynchronizer
    private let structuralMutations: TabStructuralCollectionMutationOwner

    init(
        store: ShortcutPinStoreOwner,
        bindings: ShortcutTabBindingSynchronizer,
        structuralMutations: TabStructuralCollectionMutationOwner
    ) {
        self.store = store
        self.bindings = bindings
        self.structuralMutations = structuralMutations
    }

    func commit(
        _ pin: ShortcutPin,
        to destination: Destination,
        admission: LiveShortcutPresentationRefreshAdmission
    ) -> ShortcutPin? {
        let inserted = store.move(
            pin,
            to: destination.role,
            profileId: destination.profileID,
            spaceId: destination.spaceID,
            folderId: destination.folderID,
            index: destination.index,
            openTargetFolder: destination.opensFolder,
            applying: { [bindings] in
                bindings.refreshInstances(for: $0, admission: admission)
            }
        )
        if inserted != nil {
            structuralMutations.schedulePersistence()
        }
        return inserted
    }
}
