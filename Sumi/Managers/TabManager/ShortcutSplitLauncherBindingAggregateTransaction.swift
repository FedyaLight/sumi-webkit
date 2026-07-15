import SumiWebRuntime

@MainActor
final class ShortcutSplitLauncherBindingAggregateTransaction:
    ShortcutTabBindingAggregateTransaction {
    private enum State {
        case prepared, staged, claimed, rolledBack, conflicted, terminal
    }

    private let model: any ShortcutSplitLauncherBindingModelTransaction
    private let structuralMutations: TabStructuralCollectionMutationOwner
    private let structuralLookup: TabStructuralLookupCoordinator
    private var structural: TabStructuralCollectionMutationOwner.PreparedAggregate?
    private var state = State.prepared

    var exactBindingTabs: [Tab] { model.exactBindingTabs }

    init(
        model: any ShortcutSplitLauncherBindingModelTransaction,
        structuralMutations: TabStructuralCollectionMutationOwner,
        structuralLookup: TabStructuralLookupCoordinator
    ) {
        self.model = model
        self.structuralMutations = structuralMutations
        self.structuralLookup = structuralLookup
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return model.validateForStaging()
    }

    func retainsModelAfterFailedStage() -> Bool {
        if case .conflicted = state { return true }
        return false
    }

    func stage() throws {
        guard validateForStaging() else {
            let settled = model.cancelPrepared()
            state = settled ? .terminal : .conflicted
            throw settled
                ? ShortcutTabBindingModelError.restoredAfterFailedStage
                : ShortcutSplitLauncherAggregateError.compensationFailed
        }
        guard let structural = structuralMutations.prepareAggregate() else {
            let settled = model.cancelPrepared()
            state = settled ? .terminal : .conflicted
            throw settled
                ? ShortcutTabBindingModelError.restoredAfterFailedStage
                : ShortcutSplitLauncherAggregateError.compensationFailed
        }
        self.structural = structural
        guard model.stageCatalog() else {
            try restoreAfterFailedStage()
        }
        do {
            try model.stageBinding()
        } catch {
            if model.retainsModelAfterFailedStage() {
                guard structural.stage() else {
                    state = .conflicted
                    throw ShortcutSplitLauncherAggregateError.compensationFailed
                }
                state = .conflicted
                throw error
            }
            try restoreAfterFailedStage()
        }
        guard structural.stage() else {
            do { try model.rollbackBinding() } catch {
                state = .conflicted
                throw ShortcutSplitLauncherAggregateError.compensationFailed
            }
            try restoreAfterFailedStage()
        }
        state = .staged
        guard stagedModelIsExact() else {
            try rollback()
            throw ShortcutSplitLauncherAggregateError.stale
        }
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged = state else { return false }
        return model.stagedModelIsExact() && structural?.isCurrent() == true
    }

    func canClaimTerminalModel() -> Bool { stagedModelIsExact() }

    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        guard canClaimTerminalModel(),
              model.claimTerminalModel() == .sealed else {
            return .terminallyDrained
        }
        state = .claimed
        return .sealed
    }

    func claimedModelIsExact() -> Bool {
        guard case .claimed = state else { return false }
        return model.claimedModelIsExact() && structural?.isCurrent() == true
    }

    func publishCommit() {
        guard case .claimed = state else {
            preconditionFailure("Launcher binding aggregate was not claimed")
        }
        structuralLookup.withTransaction {
            model.publishModelCommit {
                precondition(structural?.publish() == true)
            }
            model.publishTerminalEffects()
        }
        state = .terminal
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        let settled = model.cancelPrepared()
        state = settled ? .terminal : .conflicted
        return settled
    }

    func rollback() throws {
        guard stagedModelIsExact() else {
            throw ShortcutSplitLauncherAggregateError.stale
        }
        try model.rollbackBinding()
        guard structural?.rollback() == true,
              model.confirmStructuralRollback() else {
            state = .conflicted
            throw ShortcutSplitLauncherAggregateError.compensationFailed
        }
        state = .rolledBack
    }

    func publishRollback() {
        guard case .rolledBack = state else { return }
        model.publishRollback()
        state = .terminal
    }

    func canSettleTerminalDrain() -> Bool {
        switch state {
        case .staged, .claimed, .conflicted:
            return model.canSettleTerminalDrain()
                && structural?.canAbandonForTerminalDrain() == true
        case .rolledBack, .terminal:
            return true
        case .prepared:
            return false
        }
    }

    func settleTerminalDrain() -> Bool {
        if case .terminal = state { return true }
        if case .rolledBack = state {
            guard model.settleTerminalDrain() else { return false }
            state = .terminal
            return true
        }
        guard canSettleTerminalDrain() else { return false }
        precondition(model.settleTerminalDrain())
        structural?.abandonForTerminalDrain()
        state = .terminal
        return true
    }

    private func restoreAfterFailedStage() throws -> Never {
        guard structural?.rollback() == true,
              model.confirmStructuralRollback() else {
            state = .conflicted
            throw ShortcutSplitLauncherAggregateError.compensationFailed
        }
        state = .terminal
        throw ShortcutTabBindingModelError.restoredAfterFailedStage
    }
}
