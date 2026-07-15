import Foundation

extension ShortcutSplitLauncherBindingContribution {
    enum ComposedPreparationOutcome {
        case prepared(
            binding: ShortcutSplitLauncherBindingModelParticipant,
            profiles: ShortcutTabProfileAssignmentBatch,
            targetWindowStates: [UUID: BrowserWindowShortcutMutationState]
        )
        case restored
        case conflicted
    }

    func prepareComposedTransaction(
        windows: [ShortcutTabBindingWindowContribution]
    ) -> ComposedPreparationOutcome {
        prepareComposedTransaction(additional: nil, windows: windows)
    }

    func prepareComposedTransaction(
        additional: ShortcutTabBindingBatchContribution?,
        windows: [ShortcutTabBindingWindowContribution]
    ) -> ComposedPreparationOutcome {
        let additionalResidences = ShortcutTabBindingResidenceCompositeTransaction(
            additional?.residences ?? []
        )
        guard isCurrent() else {
            return settleRejectedPreparation(
                additionalResidences: additionalResidences
            )
        }
        let combined = ShortcutTabBindingBatchContribution.combining(
            [binding, additional].compactMap { $0 }
        )
        guard let transaction = builder.makeComposedTransaction(
            from: combined,
            windows: windows
        ) else {
            return settleRejectedPreparation(
                additionalResidences: additionalResidences
            )
        }
        let model = issueModel(core: transaction.model)
        return .prepared(
            binding: model,
            profiles: transaction.profiles,
            targetWindowStates: transaction.targetWindowStates
        )
    }

    private func settleRejectedPreparation(
        additionalResidences: ShortcutTabBindingResidenceCompositeTransaction
    ) -> ComposedPreparationOutcome {
        let additionalCancelled = additionalResidences.cancelPrepared()
        let contributionCancelled = rollbackBeforeExecution()
        return additionalCancelled && contributionCancelled
            ? .restored : .conflicted
    }
}
