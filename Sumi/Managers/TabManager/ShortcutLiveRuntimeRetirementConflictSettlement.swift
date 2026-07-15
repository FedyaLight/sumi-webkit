import SumiWebRuntime

@MainActor
enum ShortcutLiveRuntimeRetirementConflictSettlement {
    static func settleBegin(
        _ batch: TabRuntimeRetirementBatch,
        residence: ShortcutLiveResidenceRetirementParticipant,
        retirement: TabRuntimeRetirementService,
        terminalModel: PreparedTabTerminalModelRetirement?
    ) -> ShortcutLiveRuntimeRetirementClaimOutcome {
        resolve(
            batch,
            sourceWasRestored: residence.compensateModelConflict(),
            retirement: retirement,
            terminalModel: terminalModel
        )
    }

    static func settleRollback(
        _ batch: TabRuntimeRetirementBatch,
        retirement: TabRuntimeRetirementService,
        terminalModel: PreparedTabTerminalModelRetirement?
    ) -> ShortcutLiveRuntimeRetirementClaimOutcome {
        switch retirement.rollback(batch) {
        case .rolledBack:
            return cancel(terminalModel) ? .restored : .conflict
        case .noLongerActive:
            switch batch.modelTransaction.state {
            case .modelRolledBack:
                return cancel(terminalModel) ? .restored : .conflict
            case .modelStaged:
                return .claimed(.terminallyDrained(batch.runtimeTabIDs))
            case .prepared, .conflicted:
                return .conflict
            }
        case .modelTransactionMismatch, .modelConflict, .conflict:
            return resolve(
                batch,
                sourceWasRestored: batch.modelTransaction.state
                    == .modelRolledBack,
                retirement: retirement,
                terminalModel: terminalModel
            )
        }
    }

    private static func resolve(
        _ batch: TabRuntimeRetirementBatch,
        sourceWasRestored: Bool,
        retirement: TabRuntimeRetirementService,
        terminalModel: PreparedTabTerminalModelRetirement?
    ) -> ShortcutLiveRuntimeRetirementClaimOutcome {
        if sourceWasRestored {
            switch retirement.restoreAfterModelCompensation(batch) {
            case .rolledBack, .noLongerActive:
                return cancel(terminalModel) ? .restored : .conflict
            case .modelTransactionMismatch, .modelConflict, .conflict:
                break
            }
        }
        switch retirement.claimCleanupAfterModelConflict(batch) {
        case .claimed(let ownership): return .conflictCleanup(ownership)
        case .noLongerActive: return sourceWasRestored ? .restored : .conflict
        }
    }

    private static func cancel(
        _ terminalModel: PreparedTabTerminalModelRetirement?
    ) -> Bool {
        terminalModel?.cancelPrepared() ?? true
    }
}
