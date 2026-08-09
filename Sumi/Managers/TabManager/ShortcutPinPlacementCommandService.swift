import Foundation
import SumiDomain

@MainActor
final class ShortcutPinPlacementCommandService {
    private let moves: ShortcutPinMoveTransaction
    private let reorders: ShortcutPinReorderTransaction

    init(
        moves: ShortcutPinMoveTransaction,
        reorders: ShortcutPinReorderTransaction
    ) {
        self.moves = moves
        self.reorders = reorders
    }

    func move(
        _ pin: ShortcutPin,
        to role: ShortcutPinRole,
        profileId: UUID?,
        spaceId: UUID?,
        folderId: UUID?,
        index: Int,
        openTargetFolder: Bool
    ) -> ShortcutPin? {
        moves.move(
            pin,
            to: role,
            profileId: profileId,
            spaceId: spaceId,
            folderId: folderId,
            index: index,
            openTargetFolder: openTargetFolder
        )
    }

    func reorderFavorite(_ pin: ShortcutPin, to index: Int) -> Bool {
        reorders.reorderFavorite(pin, to: index)
    }

    func reorderSpacePinned(
        _ pin: ShortcutPin,
        in spaceID: UUID,
        to index: Int
    ) -> Bool {
        reorders.reorderSpacePinned(pin, in: spaceID, to: index)
    }
}
