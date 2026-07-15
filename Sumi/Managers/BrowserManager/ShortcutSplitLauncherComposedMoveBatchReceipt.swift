@MainActor
final class ShortcutSplitLauncherComposedMoveBatchReceipt:
    ShortcutSplitLauncherComposedMoveBatchParticipant {
    private enum State { case prepared, executed, terminal }

    private let contribution: ShortcutSplitLauncherBindingContribution
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private var state = State.prepared

    init(
        contribution: ShortcutSplitLauncherBindingContribution,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.contribution = contribution
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
    }

    func admitPresentationIdentity(
        to presentation: PreparedWindowSplitPresentationSettlement
    ) -> Bool {
        guard case .prepared = state,
              let handoff = contribution.preparePresentationIdentityHandoff()
        else { return false }
        return presentation.admitCatalogIdentityHandoff(
            handoff
        )
    }

    func executeRestore(
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt,
        retirementService: ShortcutLiveTabRetirementService,
        folderOpenState: TabFolderOpenStateService
    ) -> PreparedProfileAssignmentBatchTransitionOutcome? {
        guard case .prepared = state else { return .conflicted }
        let presentationWindows = presentation.windowContribution
        let retirementWindows: ShortcutTabBindingWindowContribution
        if let retirement {
            guard let windows = retirement.windowContribution(
                reconcilingWith: presentationWindows
            ) else {
                let restored = cancelPreparation(
                    presentation: presentation,
                    retirement: retirement
                )
                topology.rollback()
                return restored ? .rejectedUnstaged(.stale) : .conflicted
            }
            retirementWindows = windows
        } else {
            retirementWindows = .empty
        }
        let preparation = contribution.prepareComposedTransaction(
            windows: [presentationWindows, retirementWindows]
        )
        guard case .prepared(
            let binding,
            let profiles,
            let targetWindowStates
        ) = preparation else {
            let restored = cancelExternalPreparation(
                presentation: presentation,
                retirement: retirement
            )
            topology.rollback()
            state = .terminal
            if case .conflicted = preparation { return .conflicted }
            return restored ? .rejectedUnstaged(.stale) : .conflicted
        }
        guard presentation.admitAggregateWindowStates(
            targetWindowStates
        ) else {
            let bindingCancelled = binding.cancelPrepared()
            let externalCancelled = cancelExternalPreparation(
                presentation: presentation,
                retirement: retirement
            )
            topology.rollback()
            state = .terminal
            return bindingCancelled && externalCancelled
                ? .rejectedUnstaged(.stale) : .conflicted
        }
        let participants = SplitShortcutMemberRestoreParticipants(
            presentation: presentation,
            retirement: retirement,
            topology: topology,
            retirementService: retirementService
        )
        let aggregate = SplitShortcutMemberRestoreAggregateTransaction(
            binding: binding,
            participants: participants,
            structuralMutations: structuralMutations,
            structuralLookup: structuralLookup
        )
        contribution.folders.requestCommit(
            openingFoldersWith: folderOpenState
        )
        state = .executed
        return profiles.execute(bindingModel: aggregate)
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        let cancelled = contribution.rollbackBeforeExecution()
        state = .terminal
        return cancelled
    }

    private func cancelPreparation(
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?
    ) -> Bool {
        let contributionCancelled = contribution.rollbackBeforeExecution()
        let externalCancelled = cancelExternalPreparation(
            presentation: presentation,
            retirement: retirement
        )
        state = .terminal
        return contributionCancelled && externalCancelled
    }

    private func cancelExternalPreparation(
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?
    ) -> Bool {
        let presentationCancelled = presentation.cancelPrepared()
        let retirementCancelled = retirement?.cancelPrepared() ?? true
        return presentationCancelled && retirementCancelled
    }
}
