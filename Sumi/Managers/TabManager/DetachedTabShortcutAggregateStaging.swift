@MainActor
final class DetachedTabShortcutAggregateStaging {
    private let binding: any ShortcutSplitLauncherBindingModelTransaction
    private let runtime: DetachedTabRuntimeRetirementParticipant
    private let durable: RegularTabShortcutDurableStructureParticipant

    init(
        binding: any ShortcutSplitLauncherBindingModelTransaction,
        runtime: DetachedTabRuntimeRetirementParticipant,
        durable: RegularTabShortcutDurableStructureParticipant
    ) {
        self.binding = binding
        self.runtime = runtime
        self.durable = durable
    }

    func execute() -> DetachedTabShortcutAggregateStagingOutcome {
        guard durable.begin() else {
            var restored = binding.cancelPrepared()
            if runtime.cancelPrepared() == false { restored = false }
            return rejection(restored)
        }
        switch runtime.stage() {
        case .staged:
            break
        case .requiresModelConflictCompensation:
            return compensateBeginModelConflict()
        case .rejected:
            return rejection(DetachedTabShortcutAggregateCompensation
                .beforeCatalogStage(
                    binding: binding, runtime: runtime, durable: durable
                ))
        }
        guard binding.stageCatalog() else {
            if binding.retainsModelAfterFailedStage() {
                return retainedAfterFailedStage(
                    DetachedTabShortcutAggregateError.compensationFailed
                )
            }
            return rejection(DetachedTabShortcutAggregateCompensation
                .afterFailedCatalogStage(
                    binding: binding, runtime: runtime, durable: durable
                ))
        }
        guard durable.stagePresentation() else {
            return rejection(DetachedTabShortcutAggregateCompensation
                .afterFailedPresentationStage(
                    binding: binding, runtime: runtime, durable: durable
                ))
        }
        do { try binding.stageBinding() } catch {
            if binding.retainsModelAfterFailedStage() {
                return retainedAfterFailedStage(error)
            }
            return rejection(DetachedTabShortcutAggregateCompensation
                .afterFailedCatalogStage(
                    binding: binding, runtime: runtime, durable: durable
                ))
        }
        guard durable.stage() else {
            do {
                try DetachedTabShortcutAggregateCompensation.afterBindingStage(
                    binding: binding, runtime: runtime, durable: durable
                )
                return rejection(true)
            } catch {
                return failedCompensation(error)
            }
        }
        return .staged
    }

    private func compensateBeginModelConflict()
        -> DetachedTabShortcutAggregateStagingOutcome {
        var restored = binding.cancelPrepared()
        if runtime.prepareStructuralRollback() == false { restored = false }
        if durable.rollback() == false { restored = false }
        if runtime.confirmStructuralRollback() == false { restored = false }
        guard restored == false else { return rejection(true) }
        return failedCompensation(
            DetachedTabShortcutAggregateError.compensationFailed
        )
    }

    private func retainedAfterFailedStage(
        _ error: any Error
    ) -> DetachedTabShortcutAggregateStagingOutcome {
        .failed(
            state: durable.stage()
                ? .retainedAfterFailedStage : .unsettledConflict,
            error: error
        )
    }

    private func failedCompensation(
        _ error: any Error
    ) -> DetachedTabShortcutAggregateStagingOutcome {
        .failed(
            state: runtime.retainsCleanupAfterModelConflict
                ? .runtimeCleanupRetained : .unsettledConflict,
            error: error
        )
    }

    private func rejection(
        _ restored: Bool
    ) -> DetachedTabShortcutAggregateStagingOutcome {
        .failed(
            state: restored ? .terminal : .unsettledConflict,
            error: restored
                ? DetachedTabShortcutAggregateError.stale
                : DetachedTabShortcutAggregateError.compensationFailed
        )
    }
}

enum DetachedTabShortcutAggregateStagingOutcome {
    case staged
    case failed(state: DetachedTabShortcutAggregateState, error: any Error)
}
