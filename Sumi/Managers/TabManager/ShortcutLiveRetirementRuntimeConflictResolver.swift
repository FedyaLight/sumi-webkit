enum ShortcutLiveRetirementRuntimeConflictResolution {
    case restored
    case retainedConflict
    case cleanup(CommittedTabRuntimeRetirementCleanupOwnership)
}

@MainActor
enum ShortcutLiveRetirementRuntimeConflictResolver {
    static func rejectStage(
        _ batch: TabRuntimeRetirementBatch?,
        model: ShortcutLiveRetirementBatchModelParticipant,
        retirement: TabRuntimeRetirementService
    ) -> ShortcutLiveRetirementRuntimeStageOutcome {
        guard let batch else {
            return .rejected(model.compensateBeforeRuntimeCommit())
        }
        switch retirement.rollback(batch) {
        case .rolledBack, .noLongerActive:
            return .rejected(model.compensateBeforeRuntimeCommit())
        case .modelTransactionMismatch, .modelConflict, .conflict:
            return settleStage(batch, model: model, retirement: retirement)
        }
    }

    static func settleStage(
        _ batch: TabRuntimeRetirementBatch,
        model: ShortcutLiveRetirementBatchModelParticipant,
        retirement: TabRuntimeRetirementService
    ) -> ShortcutLiveRetirementRuntimeStageOutcome {
        let compensation = model.compensateBeforeRuntimeCommit()
        switch resolve(batch, compensation: compensation, retirement: retirement) {
        case .cleanup(let ownership): return .cleanup(ownership, compensation)
        case .restored, .retainedConflict: return .rejected(compensation)
        }
    }

    static func settleClaim(
        _ batch: TabRuntimeRetirementBatch,
        model: ShortcutLiveRetirementBatchModelParticipant,
        retirement: TabRuntimeRetirementService
    ) -> ShortcutLiveRetirementRuntimeClaimOutcome {
        let compensation = model.compensateBeforeRuntimeCommit()
        switch resolve(batch, compensation: compensation, retirement: retirement) {
        case .cleanup(let ownership): return .cleanup(ownership, compensation)
        case .restored, .retainedConflict: return .rejected(compensation)
        }
    }

    static func cleanup(
        _ ownership: CommittedTabRuntimeRetirementCleanupOwnership,
        model: ShortcutLiveRetirementBatchModelParticipant,
        retirement: TabRuntimeRetirementService
    ) -> ShortcutLiveRetirementRuntimeClaimOutcome {
        .cleanup(ownership, model.compensateBeforeRuntimeCommit())
    }

    static func resolve(
        _ batch: TabRuntimeRetirementBatch,
        compensation: ShortcutLiveRetirementModelCompensation,
        retirement: TabRuntimeRetirementService
    ) -> ShortcutLiveRetirementRuntimeConflictResolution {
        if case .restored = compensation {
            switch retirement.restoreAfterModelCompensation(batch) {
            case .rolledBack, .noLongerActive:
                return .restored
            case .modelTransactionMismatch, .modelConflict, .conflict:
                break
            }
        }
        switch retirement.claimCleanupAfterModelConflict(batch) {
        case .claimed(let ownership):
            return .cleanup(ownership)
        case .noLongerActive:
            return compensation == .restored ? .restored : .retainedConflict
        }
    }
}
