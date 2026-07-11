import Foundation
import SumiDomain

struct ShortcutSplitLauncherDestination {
    let role: ShortcutPinRole
    let profileId: UUID?
    let spaceId: UUID?
    let folderId: UUID?
    let index: Int
}

/// Restores only durable shortcut-container placement and cannot mutate window
/// selection or resolve dependencies through a manager façade.
@MainActor
final class ShortcutSplitLauncherPlacementService {
    private let shortcutPin: (UUID) -> ShortcutPin?
    private let folderSpaceId: (UUID) -> UUID?
    private let topLevelItemCount: (UUID) -> Int
    private let moveShortcut: (
        ShortcutPin,
        ShortcutSplitLauncherDestination
    ) -> Void

    init(
        shortcutPin: @escaping (UUID) -> ShortcutPin?,
        folderSpaceId: @escaping (UUID) -> UUID?,
        topLevelItemCount: @escaping (UUID) -> Int,
        moveShortcut: @escaping (
            ShortcutPin,
            ShortcutSplitLauncherDestination
        ) -> Void
    ) {
        self.shortcutPin = shortcutPin
        self.folderSpaceId = folderSpaceId
        self.topLevelItemCount = topLevelItemCount
        self.moveShortcut = moveShortcut
    }

    func restore(_ member: SplitGroupMember) {
        guard let pinId = member.pinId,
              let pin = shortcutPin(pinId),
              let destination = destination(for: member, pin: pin)
        else { return }
        moveShortcut(pin, destination)
    }

    private func destination(
        for member: SplitGroupMember,
        pin: ShortcutPin
    ) -> ShortcutSplitLauncherDestination? {
        switch member.origin {
        case .essential(let profileId, let index):
            guard let targetProfileId = profileId ?? pin.profileId else {
                return nil
            }
            return ShortcutSplitLauncherDestination(
                role: .essential,
                profileId: targetProfileId,
                spaceId: nil,
                folderId: nil,
                index: index
            )
        case .spacePinned(let spaceId, let folderId, let index):
            let validFolderId = folderId.flatMap {
                folderSpaceId($0) == spaceId ? $0 : nil
            }
            return ShortcutSplitLauncherDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: validFolderId,
                index: index
            )
        case .generatedSpacePinnedFromRegular(let spaceId, _):
            return ShortcutSplitLauncherDestination(
                role: .spacePinned,
                profileId: nil,
                spaceId: spaceId,
                folderId: nil,
                index: topLevelItemCount(spaceId)
            )
        case .regular:
            return nil
        }
    }
}
