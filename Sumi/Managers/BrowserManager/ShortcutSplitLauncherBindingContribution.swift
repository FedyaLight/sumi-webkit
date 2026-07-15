@MainActor
final class ShortcutSplitLauncherBindingContribution {
    private enum State { case prepared, issued, terminal }

    let builder: ShortcutTabBindingBatchBuilder
    let binding: ShortcutTabBindingBatchContribution
    let folders: ShortcutSplitLauncherFolderPublicationGate

    private let checkpoint: ShortcutSplitLauncherMoveBatchCheckpoint
    private var state = State.prepared

    init(
        builder: ShortcutTabBindingBatchBuilder,
        binding: ShortcutTabBindingBatchContribution,
        checkpoint: ShortcutSplitLauncherMoveBatchCheckpoint,
        folders: ShortcutSplitLauncherFolderPublicationGate
    ) {
        self.builder = builder
        self.binding = binding
        self.checkpoint = checkpoint
        self.folders = folders
    }

    static func insertionOnly(
        _ insertion: ShortcutSplitLauncherCatalogInsertionPlan,
        catalog: ShortcutSplitLauncherCatalogTransaction,
        builder: ShortcutTabBindingBatchBuilder
    ) -> ShortcutSplitLauncherBindingContribution? {
        guard catalog.matches(insertion.sourceCatalog),
              builder.isCurrent() else { return nil }
        return ShortcutSplitLauncherBindingContribution(
            builder: builder,
            binding: ShortcutTabBindingBatchContribution(
                inputs: [],
                profileAdmissions: [],
                residences: []
            ),
            checkpoint: ShortcutSplitLauncherMoveBatchCheckpoint(
                catalog: catalog,
                source: insertion.sourceCatalog,
                plan: ShortcutSplitLauncherCatalogMovePlan(
                    insertion: insertion.insertion,
                    entries: []
                )
            ),
            folders: ShortcutSplitLauncherFolderPublicationGate(folderIDs: [])
        )
    }

    func isCurrent() -> Bool {
        guard case .prepared = state else { return false }
        return checkpoint.validateForStaging() && builder.isCurrent()
    }

    func preparePresentationIdentityHandoff()
        -> ShortcutPresentationCatalogIdentityHandoff? {
        checkpoint.preparePresentationIdentityHandoff()
    }

    func issueModel(
        core: ShortcutTabBindingModelTransaction
    ) -> ShortcutSplitLauncherBindingModelParticipant {
        let model = ShortcutSplitLauncherBindingModelParticipant(
            core: core,
            checkpoint: checkpoint,
            folders: folders
        )
        state = .issued
        return model
    }

    func rollbackBeforeExecution() -> Bool {
        switch state {
        case .prepared:
            let residences = ShortcutTabBindingResidenceCompositeTransaction(
                binding.residences
            )
            let residencesCancelled = residences.cancelPrepared()
            let checkpointCancelled = checkpoint.cancelPrepared()
            folders.bindingDidRollback()
            guard residencesCancelled, checkpointCancelled else {
                state = .terminal
                return false
            }
        case .issued:
            return false
        case .terminal:
            return false
        }
        state = .terminal
        return true
    }
}
