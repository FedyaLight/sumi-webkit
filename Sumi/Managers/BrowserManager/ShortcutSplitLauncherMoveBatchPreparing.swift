@MainActor
protocol ShortcutSplitLauncherMoveBatchParticipant: AnyObject {
    func isCurrent() -> Bool
    func canRollback() -> Bool
    func rollback() -> Bool
    func settleAdmittedModel()
    func publishAndExecute()
}

@MainActor
protocol ShortcutSplitLauncherMoveBatchPreparing: AnyObject {
    func accepts(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) -> Bool

    func prepare(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?

    func prepareForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?
}
