@MainActor
final class SplitShortcutMemberRestoreParticipants {
    enum StageOutcome { case staged, cleanupRetained, restored, conflicted }
    private let presentation: PreparedWindowSplitPresentationSettlement
    private let retirement: ReversibleShortcutLiveTabRetirement?
    private let topology: SplitGroupReplacementReceipt
    private let publication: SplitShortcutMemberRestorePublication
    private var state = SplitShortcutMemberRestoreParticipantState.prepared

    init(
        presentation: PreparedWindowSplitPresentationSettlement,
        retirement: ReversibleShortcutLiveTabRetirement?,
        topology: SplitGroupReplacementReceipt,
        retirementService: ShortcutLiveTabRetirementService
    ) {
        self.presentation = presentation
        self.retirement = retirement
        self.topology = topology
        publication = SplitShortcutMemberRestorePublication(
            presentation: presentation,
            retirement: retirement,
            topology: topology,
            retirementService: retirementService
        )
    }

    func stage() -> StageOutcome {
        guard case .prepared = state else { return .conflicted }
        let outcome = SplitShortcutMemberRestoreStaging.stage(
            presentation: presentation,
            retirement: retirement,
            topology: topology
        )
        switch outcome {
        case .staged: state = .staged
        case .cleanupRetained: state = .retainedCleanupConflict
        case .restored: state = .terminal
        case .conflicted: state = .conflicted
        }
        return outcome
    }

    func acceptWindowModel() -> Bool {
        guard case .staged = state,
              presentation.acceptAggregateWindowSettlement(),
              retirement?.aggregateModelIsExact() ?? true else { return false }
        return true
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return presentation.aggregateWindowModelIsExact()
            && (retirement?.aggregateModelIsExact() ?? true)
            && topology.committedModelIsExact()
    }

    func claimTerminalModel() -> Bool {
        guard stagedModelIsExact() else { return false }
        switch retirement?.sealRuntime() ?? .claimed {
        case .claimed:
            break
        case .restored:
            state = .restoredAfterFailedClaim
            return false
        case .cleanupRetained:
            state = .retainedCleanupConflict
            return false
        case .conflicted:
            state = .conflicted
            return false
        }
        guard retirement?.acceptAggregateWindowSettlement() ?? true else {
            state = .retainedCleanupConflict
            return false
        }
        state = .claimed
        return claimedModelIsExact()
    }

    func claimedModelIsExact() -> Bool {
        guard case .claimed = state else { return false }
        return presentation.aggregateWindowModelIsExact()
            && (retirement?.claimedAggregateModelIsExact() ?? true)
            && topology.committedModelIsExact()
    }

    func commitSilentModelAndClaimTerminalEffects() -> Bool {
        guard claimedModelIsExact() else {
            return false
        }
        state = .terminalEffectsClaimed
        return publication.claim()
    }

    func publishObservableModel() {
        guard case .terminalEffectsClaimed = state else {
            preconditionFailure("Split restore terminal effects were not claimed")
        }
        state = .terminal
        publication.publishObservableModel()
    }

    func publishTerminalEffects() {
        guard case .terminal = state else {
            preconditionFailure("Split restore terminal effects were not claimed")
        }
        publication.publishTerminalEffects()
    }

    func rollbackModel() -> Bool {
        guard case .staged = state else { return false }
        let restored = SplitShortcutMemberRestoreParticipantCompensation
            .rollbackStaged(
                presentation: presentation,
                retirement: retirement,
                topology: topology
            )
        state = .terminal
        return restored
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        let cancelled = SplitShortcutMemberRestoreParticipantCompensation
            .cancelPrepared(
                presentation: presentation,
                retirement: retirement,
                topology: topology
            )
        state = .terminal
        return cancelled
    }

    func canSettleTerminalDrain() -> Bool {
        if case .staged = state { return stagedModelIsExact() }
        return SplitShortcutMemberRestoreParticipantDrain.canSettle(
            state: state,
            presentation: presentation,
            retirement: retirement,
            topology: topology
        )
    }

    func prepareTerminalDrain() -> ShortcutLiveTerminalDrainEffect? {
        guard canSettleTerminalDrain() else { return nil }
        if case .staged = state {
            _ = claimTerminalModel()
        }
        return SplitShortcutMemberRestoreParticipantDrain.prepare(
            state: &state,
            presentation: presentation,
            retirement: retirement,
            topology: topology
        )
    }
}
