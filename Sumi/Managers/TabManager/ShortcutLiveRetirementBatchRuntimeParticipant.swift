import SumiWebRuntime
@MainActor
final class ShortcutLiveRetirementBatchRuntimeParticipant {
    enum ClaimedEffect {
        case empty
        case committed(CommittedTabRuntimeRetirementCleanupOwnership)
        case terminallyDrained
    }

    private enum Stage {
        case empty, leased(TabRuntimeRetirementBatch), terminallyDrained
    }
    private enum ModelPhase { case staged, claimed }

    private enum State { case prepared, staged(Stage), claimed, terminal }

    private let plan: ShortcutLiveRetirementBatchPlan
    private let model: ShortcutLiveRetirementBatchModelParticipant
    private let retirement: TabRuntimeRetirementService
    private var state = State.prepared

    init(
        plan: ShortcutLiveRetirementBatchPlan,
        model: ShortcutLiveRetirementBatchModelParticipant,
        retirement: TabRuntimeRetirementService
    ) {
        self.plan = plan
        self.model = model
        self.retirement = retirement
    }

    func stage() -> ShortcutLiveRetirementRuntimeStageOutcome {
        guard case .prepared = state, model.isCurrent() else {
            return rejectStage()
        }
        let liveTabs = plan.tabs.filter {
            $0.webViewSession.allKnownWebViews.isEmpty == false
        }
        guard liveTabs.isEmpty == false else {
            guard model.stageResidence(), model.stageWindows() else {
                return rejectStage()
            }
            state = .staged(.empty)
            return .staged
        }
        guard let runtime = plan.runtime else { return rejectStage() }
        let receipt = WebViewRetirementModelTransactionReceipt(
            isCurrent: { [weak model] in model?.isCurrent() == true },
            commit: { [weak model] in model?.stageResidence() == true },
            rollback: { [weak model] in model?.rollbackResidence() == true }
        )
        switch retirement.begin(
            tabs: plan.tabs,
            using: runtime,
            modelTransaction: receipt
        ) {
        case .began(let batch):
            guard model.stageWindows() else {
                return rejectStage(after: batch)
            }
            state = .staged(.leased(batch))
            return .staged
        case .terminallyDrained:
            guard model.stageWindows() else { return rejectStage() }
            state = .staged(.terminallyDrained)
            return .staged
        case .modelConflict(let batch):
            state = .terminal
            return ShortcutLiveRetirementRuntimeConflictResolver.settleStage(
                batch, model: model, retirement: retirement
            )
        case .modelValidationFailed, .rejected:
            return rejectStage()
        }
    }

    func claim() -> ShortcutLiveRetirementRuntimeClaimOutcome {
        guard case .staged(let stage) = state else {
            return .rejected(.retainedConflict)
        }
        switch stage {
        case .empty:
            return claimModel(effect: .empty)
        case .terminallyDrained:
            return claimModel(effect: .terminallyDrained)
        case .leased(let batch):
            return claim(batch)
        }
    }

    func markTerminal() {
        guard case .claimed = state else {
            preconditionFailure("Shortcut runtime effect was not claimed")
        }
        state = .terminal
    }

    private func claim(_ batch: TabRuntimeRetirementBatch)
        -> ShortcutLiveRetirementRuntimeClaimOutcome {
        guard retirement.canCommit(batch) else {
            return settleRollback(batch, after: .staged)
        }
        guard model.claim() else {
            return settleRollback(batch, after: .staged)
        }
        switch retirement.commit(batch) {
        case .committed(let committed):
            guard retirement.committedRetirementIsExact(committed),
                  model.claimedModelAndAttachmentAreExact() else {
                state = .terminal
                return ShortcutLiveRetirementRuntimeConflictResolver.cleanup(
                    committed, model: model, retirement: retirement
                )
            }
            state = .claimed
            return .claimed(.committed(committed))
        case .cleanupOnly(let ownership):
            state = .terminal
            return ShortcutLiveRetirementRuntimeConflictResolver.cleanup(
                ownership, model: model, retirement: retirement
            )
        case .noLongerActive:
            return claimDrained(after: .claimed)
        case .conflict:
            return settleRollback(batch, after: .claimed)
        }
    }

    private func claimModel(effect: ClaimedEffect)
        -> ShortcutLiveRetirementRuntimeClaimOutcome {
        guard model.claim() else { return rejectClaim() }
        state = .claimed
        return .claimed(effect)
    }

    private func claimDrained(after phase: ModelPhase)
        -> ShortcutLiveRetirementRuntimeClaimOutcome {
        let exact: Bool
        switch phase {
        case .staged: exact = model.claim()
        case .claimed: exact = model.claimedModelAndAttachmentAreExact()
        }
        guard exact else { return rejectClaim() }
        state = .claimed
        return .claimed(.terminallyDrained)
    }

    private func settleRollback(
        _ batch: TabRuntimeRetirementBatch,
        after phase: ModelPhase
    ) -> ShortcutLiveRetirementRuntimeClaimOutcome {
        switch retirement.rollback(batch) {
        case .noLongerActive:
            return claimDrained(after: phase)
        case .rolledBack:
            return rejectClaim()
        case .modelTransactionMismatch, .modelConflict, .conflict:
            state = .terminal
            return ShortcutLiveRetirementRuntimeConflictResolver.settleClaim(
                batch, model: model, retirement: retirement
            )
        }
    }

    private func rejectStage(
        after batch: TabRuntimeRetirementBatch? = nil
    ) -> ShortcutLiveRetirementRuntimeStageOutcome {
        state = .terminal
        return ShortcutLiveRetirementRuntimeConflictResolver.rejectStage(
            batch, model: model, retirement: retirement
        )
    }

    private func rejectClaim() -> ShortcutLiveRetirementRuntimeClaimOutcome {
        let compensation = model.compensateBeforeRuntimeCommit()
        state = .terminal
        return .rejected(compensation)
    }
}
