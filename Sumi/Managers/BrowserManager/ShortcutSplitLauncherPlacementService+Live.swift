import Foundation

@MainActor
extension ShortcutSplitLauncherPlacementService {
    convenience init(liveBrowserManager browserManager: BrowserManager) {
        let tabManager = browserManager.tabManager
        self.init(
            shortcutPin: { [weak tabManager] pinId in
                tabManager?.shortcutPinCollectionStateOwner
                    .shortcutPin(by: pinId)
            },
            folderSpaceId: { [weak tabManager] folderId in
                tabManager?.folderCollectionStateOwner.spaceId(for: folderId)
            },
            topLevelItemCount: { [weak tabManager] spaceId in
                tabManager?.spacePinnedStructureOwner
                    .topLevelSpacePinnedItems(for: spaceId).count ?? 0
            },
            moveShortcut: { [weak tabManager] pin, destination in
                _ = tabManager?.shortcutPinCommandOwner.moveShortcutPin(
                    pin,
                    to: destination.role,
                    profileId: destination.profileId,
                    spaceId: destination.spaceId,
                    folderId: destination.folderId,
                    index: destination.index,
                    openTargetFolder: destination.folderId != nil
                )
            }
        )
    }
}
