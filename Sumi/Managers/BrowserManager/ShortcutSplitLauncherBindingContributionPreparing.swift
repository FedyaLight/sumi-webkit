@MainActor
protocol ShortcutSplitLauncherBindingContributionPreparing: AnyObject {
    func prepareBindingContributionForComposedResidenceAggregate(
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> ShortcutSplitLauncherBindingContribution?

    func preflightBindingContribution(
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> ShortcutSplitLauncherBindingPreflight?

    func prepareBindingContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution?
}
