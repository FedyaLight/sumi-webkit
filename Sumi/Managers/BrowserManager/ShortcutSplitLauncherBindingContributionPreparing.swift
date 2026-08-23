@MainActor
protocol ShortcutSplitLauncherBindingContributionPreparing: AnyObject {
    func preflightBindingContribution(
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> ShortcutSplitLauncherBindingPreflight?

    func prepareBindingContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution?
}
