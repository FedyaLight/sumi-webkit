import Foundation

@MainActor
enum ShortcutPinCommandComposition {
    static func makePlacement(
        pins: ShortcutPinCollectionStateOwner,
        structuralLookup: TabStructuralLookupCoordinator,
        structuralMutations: TabStructuralCollectionMutationOwner,
        runtimeConnection: TabRuntimePortConnection,
        store: ShortcutPinStoreOwner,
        spacePinnedStructure: SpacePinnedStructureOwner,
        spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction,
        bindings: ShortcutTabBindingSynchronizer,
        essentialsVisualOrder: EssentialsVisualOrderTransaction
    ) -> ShortcutPinPlacementCommandService {
        ShortcutPinPlacementCommandService(
            moves: ShortcutPinMoveTransaction(
                structuralLookup: structuralLookup,
                preparer: ShortcutPinMovePreparer(
                    runtimeConnection: runtimeConnection,
                    pins: pins,
                    store: store,
                    bindings: bindings
                ),
                runtimeConnection: runtimeConnection,
                store: store,
                bindings: bindings,
                structuralMutations: structuralMutations
            ),
            reorders: ShortcutPinReorderTransaction(
                structuralLookup: structuralLookup,
                pins: pins,
                runtimeConnection: runtimeConnection,
                spacePinnedVisualOrder: spacePinnedVisualOrder,
                essentialsVisualOrder: essentialsVisualOrder
            )
        )
    }
}
