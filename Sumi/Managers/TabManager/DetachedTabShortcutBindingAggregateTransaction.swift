import SumiWebRuntime
@MainActor
final class DetachedTabShortcutBindingAggregateTransaction: ShortcutTabBindingAggregateTransaction {
    private let binding: any ShortcutSplitLauncherBindingModelTransaction
    private let runtime: DetachedTabRuntimeRetirementParticipant
    private let durable: RegularTabShortcutDurableStructureParticipant
    private let staging: DetachedTabShortcutAggregateStaging
    private let publication: DetachedTabShortcutCommitPublication
    private var state = DetachedTabShortcutAggregateState.prepared
    var exactBindingTabs: [Tab] { binding.exactBindingTabs }
    init(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DetachedTabRuntimeRetirementParticipant,
        durable: RegularTabShortcutDurableStructureParticipant,
        terminal: RegularTabShortcutTerminalEffects,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.binding = binding
        self.runtime = runtime
        self.durable = durable
        staging = DetachedTabShortcutAggregateStaging(
            binding: binding,
            runtime: runtime,
            durable: durable
        )
        publication = DetachedTabShortcutCommitPublication(
            terminal: terminal,
            structuralLookup: structuralLookup
        )
    }
    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return binding.validateForStaging()
            && runtime.validateForStaging()
            && durable.validateForStaging()
    }
    func retainsModelAfterFailedStage() -> Bool { state.retainsModelAfterFailedStage }
    func stage() throws {
        guard validateForStaging() else { try reject(cancelPrepared()) }
        switch staging.execute() {
        case .staged:
            state = .staged
        case .failed(let failedState, let error):
            state = failedState
            throw error
        }
        guard stagedModelIsExact() else { try rollback(); try reject(true) }
    }
    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return binding.stagedModelIsExact()
            && runtime.stagedModelIsExact()
            && durable.isCurrent()
    }
    func canClaimTerminalModel() -> Bool { stagedModelIsExact() && binding.canClaimTerminalModel() }
    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard canClaimTerminalModel() else {
            state = .unsettledConflict
            return .terminallyDrained
        }
        guard runtime.claimTerminalModel() else {
            state = runtime.canSettleTerminalDrain()
                ? .retainedAfterFailedClaim : .unsettledConflict
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
            && runtime.claimedModelIsExact()
            && durable.isCurrent()
    }
    func publishCommit() {
        precondition(claimedModelIsExact())
        state = .draining
        publication.publishModel(
            binding: binding,
            runtime: runtime,
            durable: durable
        )
        state = .terminal
        publication.publishTerminalEffects(runtime)
    }
    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        var settled = binding.cancelPrepared()
        if runtime.cancelPrepared() == false { settled = false }
        if durable.cancelPrepared() == false { settled = false }
        state = settled ? .terminal : .unsettledConflict
        return settled
    }
    func rollback() throws {
        guard stagedModelIsExact() else {
            throw DetachedTabShortcutAggregateError.stale
        }
        do {
            try DetachedTabShortcutAggregateCompensation.afterBindingStage(
                binding: binding, runtime: runtime, durable: durable
            )
            state = .rolledBack
        } catch {
            state = runtime.retainsCleanupAfterModelConflict
                ? .runtimeCleanupRetained : .unsettledConflict
            throw error
        }
    }
    func publishRollback() {
        guard case .rolledBack = state else { return }
        binding.publishRollback(); state = .terminal
    }
    func canSettleTerminalDrain() -> Bool {
        if state.acceptsReentrantDrain { return true }
        if case .rolledBack = state { return true }
        if case .runtimeCleanupRetained = state {
            return runtime.canSettleTerminalDrain()
        }
        return state.admitsRetainedDrain
            && binding.canSettleTerminalDrain()
            && runtime.canSettleTerminalDrain()
            && durable.prepareTerminalDrain() != nil
    }
    func settleTerminalDrain() -> Bool {
        if state.acceptsReentrantDrain { return true }
        if case .rolledBack = state {
            guard binding.settleTerminalDrain() else { return false }
            state = .terminal
            return true
        }
        if case .runtimeCleanupRetained = state {
            guard runtime.settleTerminalDrain() else { return false }
            state = .terminal
            return true
        }
        guard canSettleTerminalDrain() else {
            state = .unsettledConflict
            return false
        }
        guard let durableDrain = durable.prepareTerminalDrain() else {
            state = .unsettledConflict
            return false
        }
        state = .draining
        precondition(binding.settleTerminalDrain())
        durable.finishTerminalDrain(durableDrain)
        precondition(runtime.settleTerminalDrain())
        state = .terminal
        return true
    }
    private func reject(_ restored: Bool) throws -> Never {
        state = restored
            ? .terminal
            : runtime.retainsCleanupAfterModelConflict
                ? .runtimeCleanupRetained : .unsettledConflict
        throw restored
            ? DetachedTabShortcutAggregateError.stale
            : DetachedTabShortcutAggregateError.compensationFailed
    }
}
