import SumiDomain

/// Restores only durable shortcut-container placement and cannot mutate window
/// selection or resolve dependencies through a manager façade.
@MainActor
final class ShortcutSplitLauncherPlacementService {
    private let pins: ShortcutPinCollectionStateOwner
    private let destinationResolver: ShortcutSplitLauncherDestinationResolver
    private let moves: ShortcutSplitLauncherMoveTransaction

    init(
        pins: ShortcutPinCollectionStateOwner,
        destinationResolver: ShortcutSplitLauncherDestinationResolver,
        moves: ShortcutSplitLauncherMoveTransaction
    ) {
        self.pins = pins
        self.destinationResolver = destinationResolver
        self.moves = moves
    }

    func prepareRestoration(
        for member: SplitMember
    ) -> PreparedShortcutSplitLauncherRestoration? {
        guard case .shortcutPin(let pinID) = member.memberID,
              let pin = pins.shortcutPin(by: pinID),
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
    ) -> PreparedShortcutSplitLauncherRestorationBatch? {
        let shortcutMembers = members.filter {
            if case .shortcutPin = $0.memberID { return true }
            return false
        }
        let restorations = shortcutMembers.compactMap(prepareRestoration(for:))
        guard restorations.count == shortcutMembers.count,
              Set(restorations.map { $0.pin.id }).count == restorations.count else {
            return nil
        }
        return PreparedShortcutSplitLauncherRestorationBatch(
            restorations: restorations,
            moves: moves
        )
    }

    /// Proves the request before structural mutation, then retains the exact
    /// planner so staging can re-admit canonical pins after the candidate
    /// insertion's expected reindexing.
    func prepareSidebarMutation(
        for members: [SplitMember]
    ) -> RegularTabShortcutSidebarMutationPreparation? {
        guard let restorations = prepareRestorations(for: members) else {
            return nil
        }
        return .launcher(restorations)
    }
}
