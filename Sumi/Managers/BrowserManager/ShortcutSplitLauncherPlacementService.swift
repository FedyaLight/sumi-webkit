import SumiDomain

/// Prepares an all-or-nothing launcher move for every shortcut in a split.
@MainActor
final class ShortcutSplitLauncherPlacementService {
    private let pins: ShortcutPinCollectionStateOwner
    private let moves: ShortcutSplitLauncherMoveTransaction

    init(
        pins: ShortcutPinCollectionStateOwner,
        moves: ShortcutSplitLauncherMoveTransaction
    ) {
        self.pins = pins
        self.moves = moves
    }

    func prepareMoves(
        for group: SplitGroup,
        destination: (ShortcutPin, Int) -> ShortcutSplitLauncherDestination?
    ) -> PreparedShortcutSplitLauncherMoveBatch? {
        let prepared = group.memberIDs.enumerated().compactMap { offset, memberID
            -> PreparedShortcutSplitLauncherMove? in
            guard case .shortcutPin(let pinID) = memberID,
                  let pin = pins.shortcutPin(by: pinID),
                  let target = destination(pin, offset),
                  moves.accepts(pin, destination: target) else {
                return nil
            }
            return PreparedShortcutSplitLauncherMove(
                pin: pin,
                destination: target
            )
        }
        guard prepared.count == group.memberIDs.count,
              Set(prepared.map { $0.pin.id }).count == prepared.count else {
            return nil
        }
        return PreparedShortcutSplitLauncherMoveBatch(
            preparedMoves: prepared,
            moves: moves
        )
    }

    func prepareMove(
        for memberID: SplitMemberID,
        to destination: ShortcutSplitLauncherDestination
    ) -> PreparedShortcutSplitLauncherMoveBatch? {
        guard case .shortcutPin(let pinID) = memberID,
              let pin = pins.shortcutPin(by: pinID),
              moves.accepts(pin, destination: destination) else {
            return nil
        }
        return PreparedShortcutSplitLauncherMoveBatch(
            preparedMoves: [
                PreparedShortcutSplitLauncherMove(
                    pin: pin,
                    destination: destination
                ),
            ],
            moves: moves
        )
    }
}
