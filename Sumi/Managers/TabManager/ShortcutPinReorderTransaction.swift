import Foundation
import SumiDomain

@MainActor
final class ShortcutPinReorderTransaction {
    private let structuralLookup: TabStructuralLookupCoordinator
    private let liveFolders: ShortcutLiveFolderPlacementReconciler
    private let spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction
    private let favoriteVisualOrder: FavoriteVisualOrderTransaction

    init(
        structuralLookup: TabStructuralLookupCoordinator,
        liveFolders: ShortcutLiveFolderPlacementReconciler,
        spacePinnedVisualOrder: SpacePinnedVisualOrderTransaction,
        favoriteVisualOrder: FavoriteVisualOrderTransaction
    ) {
        self.structuralLookup = structuralLookup
        self.liveFolders = liveFolders
        self.spacePinnedVisualOrder = spacePinnedVisualOrder
        self.favoriteVisualOrder = favoriteVisualOrder
    }

    func reorderFavorite(_ pin: ShortcutPin, to index: Int) -> Bool {
        structuralLookup.withTransaction {
            guard self.liveFolders.isCurrent(pin) else { return false }
            guard let profileID = pin.profileId else { return false }
            return favoriteVisualOrder.reorder(
                .shortcut(pin.id),
                for: profileID,
                to: index
            )
        }
    }

    func reorderSpacePinned(
        _ pin: ShortcutPin,
        in spaceID: UUID,
        to index: Int
    ) -> Bool {
        structuralLookup.withTransaction {
            guard self.liveFolders.isCurrent(pin) else { return false }
            if pin.folderId == nil {
                return self.spacePinnedVisualOrder.reorder(
                    .shortcut(pin.id),
                    in: spaceID,
                    to: index
                )
            }
            guard let folderID = pin.folderId,
                  self.liveFolders.isLiveFolder(folderID)
            else {
                return self.spacePinnedVisualOrder.reorder(
                    .shortcut(pin.id),
                    in: spaceID,
                    folderID: pin.folderId,
                    to: index
                )
            }
            guard self.spacePinnedVisualOrder.reorder(
                .shortcut(pin.id),
                in: spaceID,
                folderID: folderID,
                to: index
            ) else { return false }
            self.liveFolders.reconcileReorder(
                pin,
                in: folderID,
                spaceID: spaceID
            )
            return true
        }
    }
}
