enum DetachedTabRuntimeRetirementCompensationOutcome {
    case awaiting(DetachedTabRuntimeStructuralRollback)
    case rejected
}

@MainActor
final class DetachedTabRuntimeRetirementCompensation {
    private let source: DetachedTabShortcutSourceModelTransaction
    private let terminal: DetachedTabTerminalRetirementPublisher

    init(
        source: DetachedTabShortcutSourceModelTransaction,
        terminal: DetachedTabTerminalRetirementPublisher
    ) {
        self.source = source
        self.terminal = terminal
    }

    func stageSource() -> Bool { source.stage() }

    func prepareSourceRollback()
        -> DetachedTabRuntimeRetirementCompensationOutcome {
        source.prepareStructuralRollback()
            ? .awaiting(.repositoryRestored)
            : .rejected
    }

    func prepareRollback(
        from stage: DetachedTabRuntimeRetirementStage,
        conflicts: DetachedTabRuntimeRetirementConflictRecovery
    ) -> DetachedTabRuntimeRetirementCompensationOutcome {
        switch stage {
        case .none, .empty:
            return prepareSourceRollback()
        case .leased(let batch):
            return conflicts.prepareLeasedRollback(batch)
        }
    }

    func confirmSourceRollback() -> Bool {
        source.confirmStructuralRollback()
    }

    func finishRestoredRollback() -> Bool {
        guard confirmSourceRollback() else { return false }
        return terminal.cancelPrepared()
    }

    func cancelPrepared() -> Bool {
        let sourceCancelled = source.cancelPrepared()
        let terminalCancelled = terminal.cancelPrepared()
        return sourceCancelled && terminalCancelled
    }
}
