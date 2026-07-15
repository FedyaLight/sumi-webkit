/// Retains one preflighted restoration set with the exact move transaction that
/// admitted it, preventing a caller from applying the witnesses through a
/// different launcher catalog.
@MainActor
final class PreparedShortcutSplitLauncherRestorationBatch {
    let restorations: [PreparedShortcutSplitLauncherRestoration]
    let moves: ShortcutSplitLauncherMoveTransaction

    init(
        restorations: [PreparedShortcutSplitLauncherRestoration],
        moves: ShortcutSplitLauncherMoveTransaction
    ) {
        self.restorations = restorations
        self.moves = moves
    }

    @discardableResult
    func applyAndCommit() -> Bool {
        guard let receipt = moves.stage(restorations),
              receipt.settleModel() else { return false }
        receipt.commit()
        return true
    }

    func applyForComposedResidenceAggregate(
        bindingMode: ShortcutSplitLauncherComposedBindingMode
    )
        -> (any ShortcutSplitLauncherComposedMoveBatchParticipant)? {
        moves.stageForComposedResidenceAggregate(
            restorations,
            bindingMode: bindingMode
        )
    }

    func preflightBindingContribution()
        -> ShortcutSplitLauncherBindingPreflight? {
        moves.preflightBindingContribution(restorations)
    }

    func prepareBindingContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution? {
        moves.prepareBindingContribution(preflight, after: insertion)
    }
}
