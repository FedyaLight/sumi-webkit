@MainActor
extension ShortcutSplitLauncherReleasePlanner {
    convenience init(tabManager: TabManager) {
        let pins = tabManager.shortcutPinCollectionStateOwner
        let folders = tabManager.folderCollectionStateOwner
        let structure = tabManager.spacePinnedStructureOwner
        self.init(
            shortcutPin: pins.shortcutPin,
            destinationResolver: ShortcutSplitLauncherDestinationResolver(
                folderSpaceID: folders.spaceId,
                topLevelItemCount: {
                    structure.topLevelSpacePinnedItems(for: $0).count
                }
            )
        )
    }
}
