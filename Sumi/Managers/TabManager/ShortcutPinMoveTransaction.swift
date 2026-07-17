import Foundation
import SumiDomain

@MainActor
final class ShortcutPinMoveTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let preparer: ShortcutPinMovePreparer
    private let store: ShortcutPinStoreOwner
    private let bindings: ShortcutTabBindingSynchronizer
    private let structuralMutations: TabStructuralCollectionMutationOwner

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        preparer: ShortcutPinMovePreparer,
        store: ShortcutPinStoreOwner,
        bindings: ShortcutTabBindingSynchronizer,
        structuralMutations: TabStructuralCollectionMutationOwner
    ) {
        self.structuralLookup = structuralLookup
        self.preparer = preparer
        self.store = store
        self.bindings = bindings
        self.structuralMutations = structuralMutations
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
            guard let admission = preparer.prepare(
                pin,
                role: role,
                profileID: profileId,
                spaceID: spaceId,
                folderID: folderId,
                index: index
            ) else { return nil }
            let inserted = store.move(
                pin,
                to: role,
                profileId: profileId,
                spaceId: spaceId,
                folderId: folderId,
                index: index,
                openTargetFolder: openTargetFolder,
                applying: { [bindings] in
                    bindings.refreshInstances(
                        for: $0,
                        admission: admission
                    )
                }
            )
            if inserted != nil { structuralMutations.schedulePersistence() }
            return inserted
        }
    }
}
