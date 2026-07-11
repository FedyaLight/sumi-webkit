import Foundation
import SumiDomain

struct ShortcutSplitLauncherDestination {
    let role: ShortcutPinRole
    let profileId: UUID?
    let spaceId: UUID?
    let folderId: UUID?
    let index: Int
}

struct PreparedShortcutSplitLauncherRestoration {
    let pin: ShortcutPin
    let destination: ShortcutSplitLauncherDestination
}

/// Restores only durable shortcut-container placement and cannot mutate window
/// selection or resolve dependencies through a manager façade.
@MainActor
final class ShortcutSplitLauncherPlacementService {
    private let shortcutPin: (UUID) -> ShortcutPin?
    private let destinationResolver: ShortcutSplitLauncherDestinationResolver
    private let moves: ShortcutSplitLauncherMoveTransaction

    init(
        shortcutPin: @escaping (UUID) -> ShortcutPin?,
        destinationResolver: ShortcutSplitLauncherDestinationResolver,
        moves: ShortcutSplitLauncherMoveTransaction
    ) {
        self.shortcutPin = shortcutPin
        self.destinationResolver = destinationResolver
        self.moves = moves
    }

    func prepareRestoration(
        for member: SplitMember
    ) -> PreparedShortcutSplitLauncherRestoration? {
        guard case .shortcutPin(let pinID) = member.memberID,
              let pin = shortcutPin(pinID),
              let destination = destinationResolver.destination(
                  for: member,
                  pin: pin
              ), moves.accepts(pin, destination: destination)
        else {
            return nil
        }
        return PreparedShortcutSplitLauncherRestoration(
            pin: pin,
            destination: destination
        )
    }

    func prepareRestorations(
        for members: [SplitMember]
    ) -> [PreparedShortcutSplitLauncherRestoration]? {
        let shortcutMembers = members.filter {
            if case .shortcutPin = $0.memberID { return true }
            return false
        }
        let restorations = shortcutMembers.compactMap(prepareRestoration(for:))
        guard restorations.count == shortcutMembers.count,
              Set(restorations.map { $0.pin.id }).count == restorations.count else {
            return nil
        }
        return restorations
    }

    @discardableResult
    func apply(_ restoration: PreparedShortcutSplitLauncherRestoration) -> Bool {
        apply([restoration])
    }

    /// Applies a preflighted batch without scheduling persistence. The caller
    /// must invoke this inside the same structural transaction as the split
    /// mutation. Unexpected catalog drift is rolled back before reporting
    /// failure.
    @discardableResult
    func apply(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> Bool {
        moves.apply(restorations)
    }
}
