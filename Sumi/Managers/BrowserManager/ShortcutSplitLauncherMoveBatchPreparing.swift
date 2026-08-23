@MainActor
protocol ShortcutSplitLauncherMoveBatchPreparing:
    ShortcutSplitLauncherBindingContributionPreparing {
    func accepts(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) -> Bool

    func prepare(
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?
}
