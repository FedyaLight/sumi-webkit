import Foundation

@MainActor
extension ShortcutSplitLauncherPlacementService {
    convenience init(liveBrowserManager browserManager: BrowserManager) {
        self.init(tabManager: { [weak browserManager] in
            browserManager?.tabManager
        })
    }

    convenience init(
        tabManager: @escaping @MainActor () -> TabManager?
    ) {
        let catalog = ShortcutSplitLauncherCatalogAdapter(
            tabManager: tabManager
        )
        self.init(
            shortcutPin: catalog.shortcutPin,
            destinationResolver: ShortcutSplitLauncherDestinationResolver(
                folderSpaceID: catalog.folderSpaceID,
                topLevelItemCount: catalog.topLevelItemCount
            ),
            moves: ShortcutSplitLauncherMoveTransaction(
                shortcutPin: catalog.shortcutPin,
                canMove: catalog.canMove,
                move: catalog.move
            )
        )
    }
}
