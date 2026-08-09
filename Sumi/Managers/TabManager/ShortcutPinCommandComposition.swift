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
        favoriteVisualOrder: FavoriteVisualOrderTransaction
    ) -> ShortcutPinPlacementCommandService {
        let liveFolders = ShortcutLiveFolderPlacementReconciler(
            pins: pins,
            runtimeConnection: runtimeConnection
        )
        return ShortcutPinPlacementCommandService(
            moves: ShortcutPinMoveTransaction(
                structuralLookup: structuralLookup,
                preparer: ShortcutPinMovePreparer(
                    liveFolders: liveFolders,
                    pins: pins,
                    store: store,
                    bindings: bindings
                ),
                liveFolders: liveFolders,
                committer: ShortcutPinMoveCommitter(
                    store: store,
                    bindings: bindings,
                    structuralMutations: structuralMutations
                )
            ),
            reorders: ShortcutPinReorderTransaction(
                structuralLookup: structuralLookup,
                liveFolders: liveFolders,
                spacePinnedVisualOrder: spacePinnedVisualOrder,
                favoriteVisualOrder: favoriteVisualOrder
            )
        )
    }
}
