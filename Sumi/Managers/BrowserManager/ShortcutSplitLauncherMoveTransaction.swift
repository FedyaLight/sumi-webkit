/// Adapts one exact launcher catalog/residence batch into the sidebar split
/// transaction. Window fields are installed as one observation-silent model
/// aggregate before terminal key publication.
@MainActor
final class ShortcutSplitLauncherMoveTransaction {
    private let batches: any ShortcutSplitLauncherMoveBatchPreparing
    private let windowMutations: BrowserWindowShortcutMutationOwner

    init(
        batches: any ShortcutSplitLauncherMoveBatchPreparing,
        windowMutations: BrowserWindowShortcutMutationOwner
    ) {
        self.batches = batches
        self.windowMutations = windowMutations
    }

    func accepts(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) -> Bool {
        batches.accepts(pin, destination: destination)
    }

    func stage(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> RegularTabShortcutSidebarMutation? {
        guard let batch = batches.prepare(restorations) else { return nil }
        return RegularTabShortcutSidebarMutation(
            batch: batch,
            windowMutations: windowMutations
        )
    }

    func stageForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> RegularTabShortcutSidebarMutation? {
        guard let batch = batches.prepareForComposedResidenceAggregate(
            restorations
        ) else { return nil }
        return RegularTabShortcutSidebarMutation(
            batch: batch,
            windowMutations: windowMutations
        )
    }
}
