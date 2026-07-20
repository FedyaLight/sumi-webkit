import SumiWebRuntime

@MainActor
final class ShortcutSplitLauncherMoveAggregateTransaction:
    ShortcutTabBindingAggregateTransaction {
    private enum State {
        case prepared, staged, retainedAfterFailedStage, claimed
        case retainedAfterFailedClaim
        case rolledBack, conflicted, terminal
    }

    private let binding: any ShortcutSplitLauncherBindingModelTransaction
    private let participants: ShortcutSplitLauncherMoveParticipants
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private var settlement: PreparedShortcutSplitLauncherMoveSettlement?
    private var state = State.prepared

    var exactBindingTabs: [Tab] { binding.exactBindingTabs }

    init(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        participants: ShortcutSplitLauncherMoveParticipants,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.binding = binding
        self.participants = participants
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return binding.validateForStaging()
    }

    func retainsModelAfterFailedStage() -> Bool {
        switch state {
        case .retainedAfterFailedStage, .conflicted: return true
        default: return false
        }
    }

    func stage() throws {
        guard case .prepared = state else {
            throw ShortcutSplitLauncherMoveAggregateError.stale
        }
        do {
            settlement = try ShortcutSplitLauncherMoveAggregateStaging.stage(
                binding: binding,
                participants: participants,
                structuralMutations: structuralMutations
            )
            state = .staged
        } catch let failure as ShortcutSplitLauncherMoveAggregateStaging.Failure {
            settlement = failure.settlement
            switch failure.disposition {
            case .terminal: state = .terminal
            case .retained: state = .retainedAfterFailedStage
            case .conflicted: state = .conflicted
            }
            throw failure.cause
        }
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return binding.stagedModelIsExact()
            && participants.stagedModelIsExact()
            && settlement?.isCurrent() == true
    }

    func canClaimTerminalModel() -> Bool {
        stagedModelIsExact() && binding.canClaimTerminalModel()
    }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard canClaimTerminalModel() else { return .terminallyDrained }
        guard participants.claimTerminalModel() else {
            state = participants.canSettleTerminalDrain()
                ? .retainedAfterFailedClaim : .conflicted
            return .terminallyDrained
        }
        guard binding.claimTerminalModel() == .sealed else {
            state = .retainedAfterFailedClaim
            return .terminallyDrained
        }
        state = .claimed
        return .sealed
    }

    func claimedModelIsExact() -> Bool {
        guard case .claimed = state else { return false }
        return binding.claimedModelIsExact()
            && participants.claimedModelIsExact()
            && settlement?.isCurrent() == true
    }

    func publishCommit() {
        guard claimedModelIsExact(), let settlement else {
            preconditionFailure("Split restore was not exactly claimed")
        }
        ShortcutSplitLauncherMoveCommitPublisher.publish(
            binding: binding,
            participants: participants,
            settlement: settlement,
            structuralLookup: structuralLookup,
            markTerminal: { state = .terminal }
        )
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        let bindingCancelled = binding.cancelPrepared()
        let participantsCancelled = participants.cancelPrepared()
        let cancelled = bindingCancelled && participantsCancelled
        state = cancelled ? .terminal : .conflicted
        return cancelled
    }

    func rollback() throws {
        guard stagedModelIsExact(), let settlement else {
            throw ShortcutSplitLauncherMoveAggregateError.stale
        }
        guard settlement.rollbackStagedModel() else {
            state = .conflicted
            throw ShortcutSplitLauncherMoveAggregateError.compensationFailed
        }
        state = .rolledBack
    }

    func publishRollback() {
        guard case .rolledBack = state else { return }
        settlement?.publishRollback()
        state = .terminal
    }

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .retainedAfterFailedStage, .claimed, .retainedAfterFailedClaim:
            return settlement?.canSettleTerminalDrain() == true
        case .rolledBack, .terminal: return true
        case .prepared, .staged, .conflicted: return false
        }
    }

    func settleTerminalDrain() -> Bool {
        guard canSettleTerminalDrain() else { return false }
        state = .terminal
        return settlement?.settleTerminalDrain() == true
    }
}
