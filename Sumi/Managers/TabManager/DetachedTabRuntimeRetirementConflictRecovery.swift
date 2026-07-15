@MainActor
final class DetachedTabRuntimeRetirementConflictRecovery {
    private let source: DetachedTabShortcutSourceModelTransaction
    private let terminal: DetachedTabTerminalRetirementPublisher
    private var rollbackPreparedSource = false

    init(
        source: DetachedTabShortcutSourceModelTransaction,
        terminal: DetachedTabTerminalRetirementPublisher
    ) {
        self.source = source
        self.terminal = terminal
    }

    func prepareBeginConflict(
        _ batch: TabRuntimeRetirementBatch
    ) -> DetachedTabRuntimeStructuralRollback {
        _ = source.prepareStructuralRollback()
        return .modelConflict(batch)
    }

    func prepareLeasedRollback(
        _ batch: TabRuntimeRetirementBatch
    ) -> DetachedTabRuntimeRetirementCompensationOutcome {
        rollbackPreparedSource = false
        switch terminal.retirement.rollback(batch) {
        case .rolledBack:
            return rollbackPreparedSource
                ? .awaiting(.repositoryRestored) : .rejected
        case .modelConflict:
            return .awaiting(.modelConflict(batch))
        case .noLongerActive, .modelTransactionMismatch, .conflict:
            return .rejected
        }
    }

    func retirementDidRollback() -> Bool {
        rollbackPreparedSource = source.prepareStructuralRollback()
        return rollbackPreparedSource
    }

    func resolveModelConflict(
        _ batch: TabRuntimeRetirementBatch
    ) -> DetachedTabRuntimeModelConflictResolution {
        guard source.confirmStructuralRollback() else {
            return retainCleanup(for: batch)
        }
        switch terminal.retirement.restoreAfterModelCompensation(batch) {
        case .rolledBack, .noLongerActive:
            return terminal.cancelPrepared() ? .restored : .conflicted
        case .modelTransactionMismatch, .modelConflict, .conflict:
            return retainCleanup(for: batch)
        }
    }

    func cleanupEffect(
        for batch: TabRuntimeRetirementBatch
    ) -> DetachedTabRuntimeRetirementEffect {
        switch terminal.retirement.claimCleanupAfterModelConflict(batch) {
        case .claimed(let cleanup): return .cleanupOnly(cleanup)
        case .noLongerActive: return .terminallyDrained
        }
    }

    func finishRetainedCleanup(
        _ cleanup: DetachedTabRuntimeRetainedCleanup
    ) -> Bool {
        let cancelled = terminal.cancelPrepared()
        if case .claimed(let ownership) = cleanup {
            terminal.retirement.destroyAfterTerminalDrain(ownership)
        }
        return cancelled
    }

    private func retainCleanup(
        for batch: TabRuntimeRetirementBatch
    ) -> DetachedTabRuntimeModelConflictResolution {
        switch terminal.retirement.claimCleanupAfterModelConflict(batch) {
        case .claimed(let cleanup): return .cleanupRetained(.claimed(cleanup))
        case .noLongerActive: return .cleanupRetained(.alreadyDrained)
        }
    }
}

enum DetachedTabRuntimeModelConflictResolution {
    case restored
    case cleanupRetained(DetachedTabRuntimeRetainedCleanup)
    case conflicted
}
