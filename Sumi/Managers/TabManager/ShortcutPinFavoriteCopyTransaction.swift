import Foundation
import SumiDomain

@MainActor
final class ShortcutPinFavoriteCopyTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let preparer: ShortcutPinFavoriteCopyPreparer
    private let store: ShortcutPinStoreOwner
    private let structuralMutations: TabStructuralCollectionMutationOwner

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        preparer: ShortcutPinFavoriteCopyPreparer,
        store: ShortcutPinStoreOwner,
        structuralMutations: TabStructuralCollectionMutationOwner
    ) {
        self.structuralLookup = structuralLookup
        self.preparer = preparer
        self.store = store
        self.structuralMutations = structuralMutations
    }

    func copy(
        _ pin: ShortcutPin,
        title: String,
        context: FavoriteShortcutPlacementOwner.TargetContext?
    ) -> ShortcutPin? {
        structuralLookup.withTransaction {
            guard let prepared = preparer.prepare(
                pin,
                title: title,
                context: context
            ), let inserted = store.insert(
                prepared.pin,
                at: prepared.insertion.index
            ) else {
                return nil
            }
            preparer.publishTargetDiagnostic(for: prepared)
            structuralMutations.schedulePersistence()
            return inserted
        }
    }
}
