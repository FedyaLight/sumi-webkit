@MainActor
protocol ShortcutSplitLauncherMoveBatchPreparing:
    ShortcutSplitLauncherBindingContributionPreparing {
    func accepts(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) -> Bool

    func prepare(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> (any ShortcutSplitLauncherMoveBatchParticipant)?

    func prepareForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration],
        bindingMode: ShortcutSplitLauncherComposedBindingMode
    ) -> (any ShortcutSplitLauncherComposedMoveBatchParticipant)?
}
