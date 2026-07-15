/// Adapts one exact launcher catalog/residence batch into the sidebar split
/// transaction. Window fields are installed as one observation-silent model
/// aggregate before terminal key publication.
@MainActor
final class ShortcutSplitLauncherMoveTransaction {
    private let batches: any ShortcutSplitLauncherMoveBatchPreparing
    private let windowMutations: BrowserWindowShortcutMutationOwner
    private let folderOpenState: TabFolderOpenStateService

    init(
        batches: any ShortcutSplitLauncherMoveBatchPreparing,
        windowMutations: BrowserWindowShortcutMutationOwner,
        folderOpenState: TabFolderOpenStateService
    ) {
        self.batches = batches
        self.windowMutations = windowMutations
        self.folderOpenState = folderOpenState
    }

    func accepts(
        _ pin: ShortcutPin,
        destination: ShortcutSplitLauncherDestination
    ) -> Bool {
        batches.accepts(pin, destination: destination)
    }

    func preflightBindingContribution(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> ShortcutSplitLauncherBindingPreflight? {
        batches.preflightBindingContribution(restorations)
    }

    func prepareBindingContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution? {
        batches.prepareBindingContribution(preflight, after: insertion)
    }

    func stage(
        _ restorations: [PreparedShortcutSplitLauncherRestoration]
    ) -> RegularTabShortcutSidebarMutation? {
        guard let batch = batches.prepare(restorations) else { return nil }
        return RegularTabShortcutSidebarMutation(
            batch: batch,
            windowMutations: windowMutations,
            folderOpenState: folderOpenState
        )
    }

    func stageForComposedResidenceAggregate(
        _ restorations: [PreparedShortcutSplitLauncherRestoration],
        bindingMode: ShortcutSplitLauncherComposedBindingMode
    ) -> (any ShortcutSplitLauncherComposedMoveBatchParticipant)? {
        batches.prepareForComposedResidenceAggregate(
            restorations,
            bindingMode: bindingMode
        )
    }
}
