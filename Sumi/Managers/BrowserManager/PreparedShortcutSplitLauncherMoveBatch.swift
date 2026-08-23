/// Retains one preflighted preparedMove set with the exact move transaction that
/// admitted it, preventing a caller from applying the witnesses through a
/// different launcher catalog.
@MainActor
final class PreparedShortcutSplitLauncherMoveBatch {
    let preparedMoves: [PreparedShortcutSplitLauncherMove]
    let moves: ShortcutSplitLauncherMoveTransaction

    init(
        preparedMoves: [PreparedShortcutSplitLauncherMove],
        moves: ShortcutSplitLauncherMoveTransaction
    ) {
        self.preparedMoves = preparedMoves
        self.moves = moves
    }

    @discardableResult
    func applyAndCommit() -> Bool {
        guard let receipt = moves.stage(preparedMoves),
              receipt.settleModel() else { return false }
        receipt.commit()
        return true
    }

    func preflightBindingContribution()
        -> ShortcutSplitLauncherBindingPreflight? {
        moves.preflightBindingContribution(preparedMoves)
    }

    func prepareBindingContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution? {
        moves.prepareBindingContribution(preflight, after: insertion)
    }
}
