@MainActor
final class DetachedTabTerminalRetirementPublisher {
    let retirement: TabRuntimeRetirementService
    private let receipt: PreparedTabTerminalModelRetirement
    private let source: DetachedTabShortcutSourceModelTransaction
    private let exposure: DetachedTabRuntimeExposureWitness
    private let teardown: TabRuntimeTeardownService
    private var effect: DetachedTabRuntimeRetirementEffect?

    init?(
        tab: Tab,
        source: DetachedTabShortcutSourceModelTransaction,
        exposure: DetachedTabRuntimeExposureWitness,
        teardown: TabRuntimeTeardownService
    ) {
        guard let receipt = teardown.terminalRetirement
            .prepareTerminalModelRetirement(
                [tab],
                sourceModelIsExact: { [weak source, exposure] in
                    source?.terminalSourceModelIsExact() == true
                        && exposure.isCurrent()
                }
            ) else {
            return nil
        }
        self.receipt = receipt
        self.source = source
        self.exposure = exposure
        self.teardown = teardown
        retirement = teardown.retirement
    }

    func isCurrent() -> Bool { receipt.isCurrent() }
    func claimModel() -> Bool { receipt.claimModel() }
    func admit(_ effect: DetachedTabRuntimeRetirementEffect) {
        precondition(self.effect == nil)
        self.effect = effect
    }

    func claimedModelIsExact() -> Bool {
        guard let effect, receipt.claimedModelIsExact() else { return false }
        return effect.isExact(exposure: exposure, retirement: retirement)
    }

    func settleModel() {
        guard let effect else {
            preconditionFailure("Detached runtime effect was not admitted")
        }
        guard let physical = DetachedTabRuntimeRetirementPhysicalEffect.normal(
            effect: effect,
            exposure: exposure,
            teardown: teardown
        ) else {
            preconditionFailure("Detached runtime physical effect became stale")
        }
        settleModel(preparing: physical)
    }

    private func settleModelForAggregateDrain() {
        guard let effect else {
            preconditionFailure("Detached runtime effect was not admitted")
        }
        guard let physical = DetachedTabRuntimeRetirementPhysicalEffect
            .aggregateDrain(
                effect: effect,
                exposure: exposure,
                teardown: teardown
            ) else {
            preconditionFailure("Detached runtime drain effect became stale")
        }
        settleModel(preparing: physical)
    }

    private func settleModel(
        preparing physical: DetachedTabRuntimeRetirementPhysicalEffect
    ) {
        precondition(receipt.commitSilentModel {
            precondition(source.commitSilentModel())
        })
        precondition(receipt.claimPhysicalEffect(preparing: {
            { physical.publish() }
        }) == .claimed)
    }

    func publishLifecycle() {
        precondition(receipt.publishLifecycle())
    }

    func finishPhysicalEffect() {
        precondition(receipt.finishPhysicalEffect())
    }

    func drain() {
        settleModelForAggregateDrain()
        publishLifecycle()
        finishPhysicalEffect()
    }

    func canSettleDrain(
        _ state: DetachedTabRuntimeRetirementParticipantState,
        stagedModelIsExact: () -> Bool,
        claimedModelIsExact: () -> Bool
    ) -> Bool {
        switch state {
        case .staged: return stagedModelIsExact()
        case .claimed: return claimedModelIsExact()
        case .modelSettled, .runtimePending, .terminal: return true
        case .prepared, .beginModelConflict, .claiming,
             .awaitingStructuralRollback, .cleanupRetained,
             .conflicted: return false
        }
    }

    func prepareDrain(
        from state: DetachedTabRuntimeRetirementParticipantState
    ) -> DetachedTabRuntimeRetirementDrainOutcome {
        switch state {
        case .modelSettled, .runtimePending, .terminal:
            return .alreadySettled
        case .staged(let stage):
            guard claimModel() else {
                _ = cancelPrepared()
                return .conflicted
            }
            switch stage.claim(using: retirement) {
            case .claimed(let effect), .requiresTerminalDrain(let effect):
                admit(effect)
            case .commitConflict(let batch):
                switch retirement.claimCleanupAfterModelConflict(batch) {
                case .claimed(let cleanup): admit(.cleanupOnly(cleanup))
                case .noLongerActive: admit(.terminallyDrained)
                }
            }
        case .claimed:
            break
        case .prepared, .beginModelConflict, .claiming,
             .awaitingStructuralRollback, .cleanupRetained, .conflicted:
            return .rejected
        }
        return .ready { [self] in drain() }
    }

    func cancelPrepared() -> Bool { receipt.cancelPrepared() }
}
