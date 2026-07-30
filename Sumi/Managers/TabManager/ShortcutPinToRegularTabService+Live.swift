import Foundation

extension ShortcutPinToRegularTabService {
    static func compose(
        promotion: ShortcutTabPromotionService,
        splitGroups: SplitGroupStore,
        splitMutations: SplitGroupMutationService,
        pinStore: ShortcutPinStoreOwner,
        pins: ShortcutPinCollectionStateOwner,
        persistence: TabStructuralPersistenceService,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeConnection: TabRuntimePortConnection
    ) -> Self {
        let transaction = ShortcutPinRegularConversionTransaction(
            promotion: promotion,
            splitMutations: splitMutations,
            pinStore: pinStore,
            persistence: persistence,
            structuralLookup: structuralLookup
        )
        let admission = ShortcutPinPromotionAdmission(
            splitGroups: splitGroups,
            pins: pins
        )
        return Self(
            singlePin: ShortcutPinRegularPromotionService(
                promotion: promotion,
                admission: admission,
                transaction: transaction,
                runtimeConnection: runtimeConnection
            ),
            group: ShortcutPinGroupRegularConversionService(
                admission: admission,
                transaction: transaction
            )
        )
    }
}
