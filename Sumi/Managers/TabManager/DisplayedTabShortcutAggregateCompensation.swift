enum DisplayedTabShortcutAggregateCompensation {
    @MainActor
    static func beforeCatalogStage(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DisplayedTabShortcutRuntimeTransaction,
        durable: RegularTabShortcutDurableStructureParticipant
    ) -> Bool {
        var restored = binding.cancelPrepared()
        if runtime.settleAfterFailedStage() == false { restored = false }
        if durable.rollback() == false { restored = false }
        return restored
    }

    @MainActor
    static func afterFailedCatalogStage(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DisplayedTabShortcutRuntimeTransaction,
        durable: RegularTabShortcutDurableStructureParticipant
    ) -> Bool {
        var restored = runtime.rollback()
        if durable.rollback() == false { restored = false }
        if binding.confirmStructuralRollback() == false { restored = false }
        return restored
    }

    @MainActor
    static func afterBindingStage(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DisplayedTabShortcutRuntimeTransaction,
        durable: RegularTabShortcutDurableStructureParticipant
    ) throws {
        var firstError: (any Error)?
        do { try binding.rollbackBinding() } catch { firstError = error }
        if runtime.rollback() == false, firstError == nil {
            firstError = DisplayedTabShortcutAggregateError.compensationFailed
        }
        if durable.rollback() == false, firstError == nil {
            firstError = DisplayedTabShortcutAggregateError.compensationFailed
        }
        if binding.confirmStructuralRollback() == false, firstError == nil {
            firstError = DisplayedTabShortcutAggregateError.compensationFailed
        }
        if let firstError { throw firstError }
    }
}

enum DisplayedTabShortcutAggregateError: Error {
    case stale
    case compensationFailed
}

enum DisplayedTabShortcutAggregateState {
    case prepared, staged, claimed, rolledBack, terminal
    case retainedAfterFailedStage, retainedAfterFailedClaim, unsettledConflict
}
