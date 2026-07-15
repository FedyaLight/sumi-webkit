@MainActor
extension ShortcutSplitLauncherPlacementService {
    convenience init(
        tabManager: TabManager
    ) {
        let pins = tabManager.shortcutPinCollectionStateOwner
        let folders = tabManager.folderCollectionStateOwner
        let spacePinnedStructure = tabManager.spacePinnedStructureOwner
        let residenceMoves = ShortcutSplitLauncherMoveBatchStaging(
            catalog: ShortcutSplitLauncherCatalogTransaction(
                pinStore: tabManager.shortcutPinStoreOwner,
                pins: pins
            ),
            bindingStaging: ShortcutSplitLauncherBindingStaging(
                tabManager: tabManager
            ),
            residenceMutations: tabManager.liveShortcutTabs.staging,
            folderOpenState: tabManager.folderOpenState
        )
        self.init(
            shortcutPin: pins.shortcutPin,
            destinationResolver: ShortcutSplitLauncherDestinationResolver(
                folderSpaceID: folders.spaceId,
                topLevelItemCount: {
                    spacePinnedStructure.topLevelSpacePinnedItems(for: $0).count
                }
            ),
            moves: ShortcutSplitLauncherMoveTransaction(
                batches: residenceMoves,
                windowMutations: tabManager.shortcutWindowMutationOwner
            )
        )
    }
}
