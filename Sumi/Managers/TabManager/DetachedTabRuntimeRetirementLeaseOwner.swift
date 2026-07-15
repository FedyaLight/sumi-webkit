import SumiWebRuntime

@MainActor
final class DetachedTabRuntimeRetirementLeaseOwner {
    private enum State { case prepared, stagingSource, sourceStaged, terminal }

    private let exposure: DetachedTabRuntimeExposureWitness
    private let terminal: DetachedTabTerminalRetirementPublisher
    private let compensation: DetachedTabRuntimeRetirementCompensation
    private let conflicts: DetachedTabRuntimeRetirementConflictRecovery
    private var state = State.prepared

    init(
        source: DetachedTabShortcutSourceModelTransaction,
        exposure: DetachedTabRuntimeExposureWitness,
        terminal: DetachedTabTerminalRetirementPublisher
    ) {
        self.exposure = exposure
        self.terminal = terminal
        compensation = DetachedTabRuntimeRetirementCompensation(
            source: source,
            terminal: terminal
        )
        conflicts = DetachedTabRuntimeRetirementConflictRecovery(
            source: source,
            terminal: terminal
        )
    }

    func validateForStaging() -> Bool {
        guard case .prepared = state else { return false }
        return terminal.isCurrent()
    }

    func begin() -> DetachedTabRuntimeLeaseBeginOutcome {
        guard validateForStaging() else { return .rejected }
        guard let runtime = exposure.runtime else {
            guard exposure.tab.webViewSession.allKnownWebViews.isEmpty,
                  stageSource() else { return .rejected }
            state = .terminal
            return .staged(.none)
        }
        let tab = exposure.tab
        guard tab.webViewSession.allKnownWebViews.isEmpty == false else {
            guard runtime.webViewLifecycle.canRetireTabWebViews([tab]),
                  stageSource() else { return .rejected }
            state = .terminal
            return .staged(.empty(runtime))
        }
        let model = WebViewRetirementModelTransactionReceipt(
            isCurrent: { [weak self] in self?.validateForStaging() == true },
            commit: { [weak self] in self?.stageSource() == true },
            rollback: { [weak conflicts] in
                conflicts?.retirementDidRollback() == true
            }
        )
        switch terminal.retirement.begin(
            tabs: [tab],
            using: runtime,
            modelTransaction: model
        ) {
        case .began(let batch):
            guard case .sourceStaged = state else { return .rejected }
            state = .terminal
            return .staged(.leased(batch))
        case .modelConflict(let batch):
            state = .terminal
            return .modelConflict(batch)
        case .terminallyDrained, .modelValidationFailed, .rejected:
            state = .terminal
            return .rejected
        }
    }

    func isExact(_ stage: DetachedTabRuntimeRetirementStage) -> Bool {
        terminal.isCurrent() && stage.isExact(
            tab: exposure.tab,
            retirement: terminal.retirement
        )
    }

    func claim(
        _ stage: DetachedTabRuntimeRetirementStage
    ) -> DetachedTabRuntimeRetirementClaimOutcome {
        stage.claim(using: terminal.retirement)
    }

    func prepareRollback(
        _ stage: DetachedTabRuntimeRetirementStage
    ) -> DetachedTabRuntimeRetirementCompensationOutcome {
        compensation.prepareRollback(from: stage, conflicts: conflicts)
    }

    func prepareSourceRollback()
        -> DetachedTabRuntimeRetirementCompensationOutcome {
        compensation.prepareSourceRollback()
    }

    func prepareBeginConflict(
        _ batch: TabRuntimeRetirementBatch
    ) -> DetachedTabRuntimeStructuralRollback {
        conflicts.prepareBeginConflict(batch)
    }

    func finishRestoredRollback() -> Bool {
        compensation.finishRestoredRollback()
    }

    func resolveModelConflict(
        _ batch: TabRuntimeRetirementBatch
    ) -> DetachedTabRuntimeModelConflictResolution {
        conflicts.resolveModelConflict(batch)
    }

    func cleanupEffect(
        for batch: TabRuntimeRetirementBatch
    ) -> DetachedTabRuntimeRetirementEffect {
        conflicts.cleanupEffect(for: batch)
    }

    func finishRetainedCleanup(
        _ cleanup: DetachedTabRuntimeRetainedCleanup
    ) -> Bool {
        conflicts.finishRetainedCleanup(cleanup)
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        state = .terminal
        return compensation.cancelPrepared()
    }

    private func stageSource() -> Bool {
        guard case .prepared = state else { return false }
        state = .stagingSource
        guard compensation.stageSource() else {
            state = .terminal
            return false
        }
        state = .sourceStaged
        return true
    }
}

enum DetachedTabRuntimeLeaseBeginOutcome {
    case staged(DetachedTabRuntimeRetirementStage)
    case modelConflict(TabRuntimeRetirementBatch)
    case rejected
}
