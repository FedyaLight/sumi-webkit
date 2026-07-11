import Foundation

/// Role-exact adapter over launcher catalog queries and moves needed by split
/// restoration. It exposes no unrelated TabManager capability.
@MainActor
final class ShortcutSplitLauncherCatalogAdapter {
    private let tabManager: @MainActor () -> TabManager?

    init(tabManager: @escaping @MainActor () -> TabManager?) {
        self.tabManager = tabManager
    }

    func shortcutPin(_ pinID: UUID) -> ShortcutPin? {
        tabManager()?.shortcutPinCollectionStateOwner.shortcutPin(by: pinID)
    }

    func folderSpaceID(_ folderID: UUID) -> UUID? {
        tabManager()?.folderCollectionStateOwner.spaceId(for: folderID)
    }

    func topLevelItemCount(_ spaceID: UUID) -> Int {
        tabManager()?.spacePinnedStructureOwner
            .topLevelSpacePinnedItems(for: spaceID).count ?? 0
    }

    func canMove(
        _ pin: ShortcutPin,
        _ destination: ShortcutSplitLauncherDestination
    ) -> Bool {
        tabManager()?.shortcutPinStoreOwner.canMove(
            pin,
            to: destination.role,
            profileId: destination.profileId,
            spaceId: destination.spaceId,
            folderId: destination.folderId
        ) == true
    }

    func move(
        _ pin: ShortcutPin,
        _ destination: ShortcutSplitLauncherDestination
    ) -> ShortcutPin? {
        guard let manager = tabManager(),
              let moved = manager.shortcutPinStoreOwner.move(
                  pin,
                  to: destination.role,
                  profileId: destination.profileId,
                  spaceId: destination.spaceId,
                  folderId: destination.folderId,
                  index: destination.index,
                  openTargetFolder: destination.folderId != nil
              ) else { return nil }
        manager.shortcutTabBindings.refreshInstances(for: moved)
        return moved
    }
}
