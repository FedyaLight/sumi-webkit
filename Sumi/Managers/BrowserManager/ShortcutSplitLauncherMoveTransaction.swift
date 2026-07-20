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
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> ShortcutSplitLauncherBindingPreflight? {
        batches.preflightBindingContribution(preparedMoves)
    }

    func prepareBindingContribution(
        _ preflight: ShortcutSplitLauncherBindingPreflight,
        after insertion: ShortcutSplitLauncherCatalogInsertionPlan
    ) -> ShortcutSplitLauncherBindingContribution? {
        batches.prepareBindingContribution(preflight, after: insertion)
    }

    func stage(
        _ preparedMoves: [PreparedShortcutSplitLauncherMove]
    ) -> RegularTabShortcutSidebarMutation? {
        guard let batch = batches.prepare(preparedMoves) else { return nil }
        return RegularTabShortcutSidebarMutation(
            batch: batch,
            windowMutations: windowMutations,
            folderOpenState: folderOpenState
        )
    }

    func stageForComposedResidenceAggregate(
        _ preparedMoves: [PreparedShortcutSplitLauncherMove],
        bindingMode: ShortcutSplitLauncherComposedBindingMode
    ) -> (any ShortcutSplitLauncherComposedMoveBatchParticipant)? {
        batches.prepareForComposedResidenceAggregate(
            preparedMoves,
            bindingMode: bindingMode
        )
    }
}
