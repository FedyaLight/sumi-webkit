import Foundation

/// Applies a preflighted launcher move batch and rolls back already moved pins
/// if catalog state drifts before the batch completes.
@MainActor
final class ShortcutSplitLauncherMoveTransaction {
    private let shortcutPin: (UUID) -> ShortcutPin?
    private let canMove: (
        ShortcutPin,
        ShortcutSplitLauncherDestination
    ) -> Bool
    private let move: (
        ShortcutPin,
        ShortcutSplitLauncherDestination
    ) -> ShortcutPin?

    init(
        shortcutPin: @escaping (UUID) -> ShortcutPin?,
        canMove: @escaping (
            ShortcutPin,
            ShortcutSplitLauncherDestination
        ) -> Bool,
        move: @escaping (
            ShortcutPin,
            ShortcutSplitLauncherDestination
        ) -> ShortcutPin?
    ) {
        self.shortcutPin = shortcutPin
        self.canMove = canMove
        self.move = move
    }

    func accepts(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) -> Bool {
        canMove(pin, destination)
    }

    func apply(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> Bool {
        guard restorations.allSatisfy({ restoration in
            guard let current = shortcutPin(restoration.pin.id) else {
                return false
            }
            return canMove(current, restoration.destination)
        }) else { return false }

        var applied: [PreparedShortcutSplitLauncherRestoration] = []
        for restoration in restorations {
            guard let current = shortcutPin(restoration.pin.id),
                  move(current, restoration.destination)?.id
                    == restoration.pin.id else {
                rollback(applied)
                return false
            }
            applied.append(restoration)
        }
        return true
    }

    private func rollback(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) {
        for restoration in restorations.reversed() {
            guard let current = shortcutPin(restoration.pin.id) else {
                continue
            }
            _ = move(
                current,
                ShortcutSplitLauncherDestination(
                    role: restoration.pin.role,
                    profileId: restoration.pin.profileId,
                    spaceId: restoration.pin.spaceId,
                    folderId: restoration.pin.folderId,
                    index: restoration.pin.index
                )
            )
        }
    }
}
