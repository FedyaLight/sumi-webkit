import Foundation

extension ShortcutPinToRegularTabService {
    static func compose(
        promotion: ShortcutTabPromotionService,
        splitGroups: SplitGroupStore,
        splitMutations: SplitGroupMutationService,
        pinStore: ShortcutPinStoreOwner,
        pins: ShortcutPinCollectionStateOwner,
        persistence: TabStructuralPersistenceService,
        structuralLookup: TabStructuralLookupCoordinator
    ) -> Self {
        let transaction = ShortcutPinRegularConversionTransaction(
            promotion: promotion,
            splitMutations: splitMutations,
            pinStore: pinStore,
            persistence: persistence,
            structuralLookup: structuralLookup
        )
        return Self(
            promotion: promotion,
            admission: ShortcutPinPromotionAdmission(
                splitGroups: splitGroups,
                pins: pins
            ),
            transaction: transaction
        )
    }
}
