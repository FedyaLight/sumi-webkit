import SumiWebRuntime
@MainActor
final class DisplayedTabShortcutBindingAggregateTransaction: ShortcutTabBindingAggregateTransaction {
    private let binding: any ShortcutSplitLauncherBindingModelTransaction
    private let runtime: DisplayedTabShortcutRuntimeTransaction
    private let durable: RegularTabShortcutDurableStructureParticipant
    private let terminal: RegularTabShortcutTerminalEffects
    private let structuralLookup: TabStructuralLookupCoordinator
    private var state = DisplayedTabShortcutAggregateState.prepared
    var exactBindingTabs: [Tab] { binding.exactBindingTabs }
    init(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DisplayedTabShortcutRuntimeTransaction,
        durable: RegularTabShortcutDurableStructureParticipant,
        terminal: RegularTabShortcutTerminalEffects,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.binding = binding
        self.runtime = runtime
        self.durable = durable
        self.terminal = terminal
        self.structuralLookup = structuralLookup
    }
    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return binding.validateForStaging()
            && runtime.validateForStaging()
            && durable.validateForStaging()
    }
    func retainsModelAfterFailedStage() -> Bool {
        switch state {
        case .retainedAfterFailedStage, .retainedAfterFailedClaim,
             .unsettledConflict: return true
        default: return false
        }
    }
    func stage() throws {
        guard validateForStaging() else { try reject(cancelPrepared()) }
        guard durable.begin() else {
            var settled = binding.cancelPrepared()
            if runtime.cancelPrepared() == false { settled = false }
            try reject(settled)
        }
        guard durable.stagePresentation() else {
            try reject(DisplayedTabShortcutAggregateCompensation
                .beforeCatalogStage(
                    binding: binding, runtime: runtime, durable: durable
                ))
        }
        guard runtime.stage() else {
            try reject(DisplayedTabShortcutAggregateCompensation
                .beforeCatalogStage(
                    binding: binding, runtime: runtime, durable: durable
                ))
        }
        guard binding.stageCatalog() else {
            if binding.retainsModelAfterFailedStage() {
                state = durable.stage()
                    ? .retainedAfterFailedStage : .unsettledConflict
                throw DisplayedTabShortcutAggregateError.compensationFailed
            }
            try reject(DisplayedTabShortcutAggregateCompensation
                .afterFailedCatalogStage(
                    binding: binding, runtime: runtime, durable: durable
                ))
        }
        do { try binding.stageBinding() } catch {
            if binding.retainsModelAfterFailedStage() {
                state = durable.stage()
                    ? .retainedAfterFailedStage : .unsettledConflict
                throw error
            }
            try reject(DisplayedTabShortcutAggregateCompensation
                .afterFailedCatalogStage(
                    binding: binding, runtime: runtime, durable: durable
                ))
        }
        guard durable.stage() else { try restoreAfterBindingStage() }
        state = .staged
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
        guard canClaimTerminalModel(),
              binding.claimTerminalModel() == .sealed else {
            state = .retainedAfterFailedClaim
            return .terminallyDrained
        }
        state = .claimed
        return .sealed
    }
    func claimedModelIsExact() -> Bool {
        guard case .claimed = state else { return false }
        return binding.claimedModelIsExact()
            && runtime.stagedModelIsExact()
            && durable.isCurrent()
    }
    func publishCommit() {
        precondition(claimedModelIsExact())
        structuralLookup.withTransaction {
            runtime.publishBeforeBinding()
            binding.publishModelCommit { durable.publishStructural() }
            runtime.publishAfterBinding()
            durable.publishTopology()
            binding.publishTerminalEffects()
            durable.publishTerminalEffects()
            terminal.publish()
        }
        state = .terminal
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
            throw DisplayedTabShortcutAggregateError.stale
        }
        do {
            try DisplayedTabShortcutAggregateCompensation.afterBindingStage(
                binding: binding, runtime: runtime, durable: durable
            )
            state = .rolledBack
        } catch { state = .unsettledConflict; throw error }
    }
    func publishRollback() {
        guard case .rolledBack = state else { return }
        binding.publishRollback(); state = .terminal
    }
    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .staged, .claimed, .retainedAfterFailedStage,
             .retainedAfterFailedClaim:
            return binding.canSettleTerminalDrain()
                && runtime.canAbandonForTerminalDrain()
                && durable.canAbandonForTerminalDrain()
        case .rolledBack: return binding.canSettleTerminalDrain()
        case .terminal: return true
        case .prepared, .unsettledConflict: return false
        }
    }
    func settleTerminalDrain() -> Bool {
        if case .terminal = state { return true }
        if case .rolledBack = state {
            guard binding.settleTerminalDrain() else { return false }
            state = .terminal
            return true
        }
        guard canSettleTerminalDrain() else {
            state = .unsettledConflict
            return false
        }
        precondition(binding.settleTerminalDrain())
        runtime.abandonForTerminalDrain()
        durable.abandonForTerminalDrain()
        state = .terminal
        return true
    }
    private func restoreAfterBindingStage() throws -> Never {
        do {
            try DisplayedTabShortcutAggregateCompensation.afterBindingStage(
                binding: binding, runtime: runtime, durable: durable
            )
            try reject(true)
        } catch { state = .unsettledConflict; throw error }
    }
    private func reject(_ restored: Bool) throws -> Never {
        state = restored ? .terminal : .unsettledConflict
        throw restored
            ? DisplayedTabShortcutAggregateError.stale
            : DisplayedTabShortcutAggregateError.compensationFailed
    }
}
