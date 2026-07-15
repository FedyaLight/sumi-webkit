enum DetachedTabShortcutAggregateCompensation {
    @MainActor
    static func beforeCatalogStage(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DetachedTabRuntimeRetirementParticipant,
        durable: RegularTabShortcutDurableStructureParticipant
    ) -> Bool {
        var restored = binding.cancelPrepared()
        if runtime.prepareStructuralRollback() == false { restored = false }
        if durable.rollback() == false { restored = false }
        if runtime.confirmStructuralRollback() == false { restored = false }
        return restored
    }

    @MainActor
    static func afterFailedCatalogStage(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DetachedTabRuntimeRetirementParticipant,
        durable: RegularTabShortcutDurableStructureParticipant
    ) -> Bool {
        var restored = runtime.prepareStructuralRollback()
        if durable.rollback() == false { restored = false }
        if binding.confirmStructuralRollback() == false { restored = false }
        if runtime.confirmStructuralRollback() == false { restored = false }
        return restored
    }

    @MainActor
    static func afterFailedPresentationStage(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DetachedTabRuntimeRetirementParticipant,
        durable: RegularTabShortcutDurableStructureParticipant
    ) -> Bool {
        guard binding.prepareStructuralRollbackAfterCatalogStage() else {
            return false
        }
        return afterFailedCatalogStage(
            binding: binding,
            runtime: runtime,
            durable: durable
        )
    }

    @MainActor
    static func afterBindingStage(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DetachedTabRuntimeRetirementParticipant,
        durable: RegularTabShortcutDurableStructureParticipant
    ) throws {
        var firstError: (any Error)?
        do { try binding.rollbackBinding() } catch { firstError = error }
        if runtime.prepareStructuralRollback() == false, firstError == nil {
            firstError = DetachedTabShortcutAggregateError.compensationFailed
        }
        if durable.rollback() == false, firstError == nil {
            firstError = DetachedTabShortcutAggregateError.compensationFailed
        }
        if binding.confirmStructuralRollback() == false, firstError == nil {
            firstError = DetachedTabShortcutAggregateError.compensationFailed
        }
        if runtime.confirmStructuralRollback() == false, firstError == nil {
            firstError = DetachedTabShortcutAggregateError.compensationFailed
        }
        if let firstError { throw firstError }
    }
}

enum DetachedTabShortcutAggregateState {
    case prepared, staged, claimed, rolledBack, draining, terminal
    case retainedAfterFailedStage, retainedAfterFailedClaim
    case runtimeCleanupRetained, unsettledConflict

    var retainsModelAfterFailedStage: Bool {
        switch self {
        case .retainedAfterFailedStage, .retainedAfterFailedClaim,
             .runtimeCleanupRetained, .unsettledConflict: return true
        default: return false
        }
    }

    var admitsRetainedDrain: Bool {
        switch self {
        case .staged, .claimed, .retainedAfterFailedStage,
             .retainedAfterFailedClaim: return true
        default: return false
        }
    }

    var acceptsReentrantDrain: Bool {
        switch self {
        case .draining, .terminal: return true
        default: return false
        }
    }
}

enum DetachedTabShortcutAggregateError: Error {
    case stale
    case compensationFailed
}
