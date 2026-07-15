@MainActor
final class DetachedTabRuntimeRetirementParticipant {
    private let terminal: DetachedTabTerminalRetirementPublisher
    private let leases: DetachedTabRuntimeRetirementLeaseOwner
    private var state = DetachedTabRuntimeRetirementParticipantState.prepared

    init(
        source: DetachedTabShortcutSourceModelTransaction,
        exposure: DetachedTabRuntimeExposureWitness,
        terminal: DetachedTabTerminalRetirementPublisher
    ) {
        self.terminal = terminal
        leases = DetachedTabRuntimeRetirementLeaseOwner(
            source: source,
            exposure: exposure,
            terminal: terminal
        )
    }

    func validateForStaging() -> Bool {
        if case .prepared = state { return leases.validateForStaging() }
        return false
    }

    func stage() -> DetachedTabRuntimeRetirementStagingOutcome {
        switch leases.begin() {
        case .staged(let stage):
            state = .staged(stage)
            return stagedModelIsExact() ? .staged : .rejected
        case .modelConflict(let batch):
            state = .beginModelConflict(batch)
            return .requiresModelConflictCompensation
        case .rejected:
            return .rejected
        }
    }

    func stagedModelIsExact() -> Bool {
        guard case .staged(let runtimeStage) = state else { return false }
        return leases.isExact(runtimeStage)
    }

    func claimTerminalModel() -> Bool {
        guard stagedModelIsExact(),
              case .staged(let runtimeStage) = state else { return false }
        state = .claiming
        guard terminal.claimModel() else {
            state = .conflicted
            return false
        }
        switch leases.claim(runtimeStage) {
        case .claimed(let effect):
            terminal.admit(effect)
            state = .claimed
            return true
        case .requiresTerminalDrain(let effect):
            terminal.admit(effect)
            state = .claimed
            return false
        case .commitConflict(let batch):
            terminal.admit(leases.cleanupEffect(for: batch))
            state = .claimed
            return false
        }
    }

    func claimedModelIsExact() -> Bool {
        guard case .claimed = state else { return false }
        return terminal.claimedModelIsExact()
    }

    var retainsCleanupAfterModelConflict: Bool {
        state.retainsCleanup
    }

    func prepareStructuralRollback() -> Bool {
        let outcome: DetachedTabRuntimeRetirementCompensationOutcome
        switch state {
        case .prepared:
            outcome = leases.prepareSourceRollback()
        case .beginModelConflict(let batch):
            outcome = .awaiting(leases.prepareBeginConflict(batch))
        case .staged(let runtimeStage):
            outcome = leases.prepareRollback(runtimeStage)
        case .awaitingStructuralRollback:
            return true
        case .cleanupRetained, .claiming, .claimed, .modelSettled,
             .runtimePending, .conflicted, .terminal:
            return false
        }
        guard case .awaiting(let rollback) = outcome else { return false }
        state = .awaitingStructuralRollback(rollback)
        return true
    }

    func confirmStructuralRollback() -> Bool {
        guard case .awaitingStructuralRollback(let rollback) = state else {
            return false
        }
        state = .conflicted
        switch rollback {
        case .repositoryRestored:
            guard leases.finishRestoredRollback() else { return false }
            state = .terminal
            return true
        case .modelConflict(let batch):
            switch leases.resolveModelConflict(batch) {
            case .restored:
                state = .terminal
                return true
            case .cleanupRetained(let cleanup):
                state = .cleanupRetained(cleanup)
                return false
            case .conflicted:
                state = .conflicted
                return false
            }
        }
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state,
              leases.cancelPrepared() else { return false }
        state = .terminal
        return true
    }

    func settleTerminalModel() {
        guard case .claimed = state else {
            preconditionFailure("Detached runtime model was not claimed")
        }
        state = .modelSettled
        terminal.settleModel()
    }

    func publishTerminalModelEffects() {
        guard case .modelSettled = state else {
            preconditionFailure("Detached terminal model was not settled")
        }
        state = .runtimePending
        terminal.publishLifecycle()
    }

    func publishRuntimeEffects() {
        guard case .runtimePending = state else {
            preconditionFailure("Detached terminal model was not published")
        }
        state = .terminal
        terminal.finishPhysicalEffect()
    }

    func canSettleTerminalDrain() -> Bool {
        if case .cleanupRetained = state { return true }
        return terminal.canSettleDrain(
            state,
            stagedModelIsExact: stagedModelIsExact,
            claimedModelIsExact: claimedModelIsExact
        )
    }

    func settleTerminalDrain() -> Bool {
        if case .cleanupRetained(let cleanup) = state {
            state = .terminal
            return leases.finishRetainedCleanup(cleanup)
        }
        switch terminal.prepareDrain(from: state) {
        case .alreadySettled:
            return true
        case .ready(let publication):
            state = .terminal
            publication()
            return true
        case .conflicted:
            state = .conflicted
            return false
        case .rejected:
            return false
        }
    }
}
