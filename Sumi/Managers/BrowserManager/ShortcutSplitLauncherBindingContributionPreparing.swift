@MainActor
protocol ShortcutSplitLauncherBindingContributionPreparing: AnyObject {
    func prepareBindingContributionForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> ShortcutSplitLauncherBindingContribution?

    func preflightBindingContribution(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> ShortcutSplitLauncherBindingPreflight?

    func prepareBindingContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution?
}
