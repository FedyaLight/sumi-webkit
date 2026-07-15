@MainActor
final class ShortcutLiveRuntimeRetirementPublication {
    private let plan: ShortcutLiveTabRetirementPlan
    private let residence: ShortcutLiveResidenceRetirementParticipant
    private let terminalModel: PreparedTabTerminalModelRetirement?
    private let effect: ShortcutLiveRuntimeRetirementEffect
    private let physical: ShortcutLiveTabRetirementPhysicalEffect?
    private let terminalDrain: ShortcutLiveTerminalDrainEffect?
    private var isConsumed = false

    init(
        plan: ShortcutLiveTabRetirementPlan,
        residence: ShortcutLiveResidenceRetirementParticipant,
        terminalModel: PreparedTabTerminalModelRetirement?,
        effect: ShortcutLiveRuntimeRetirementEffect,
        teardown: TabRuntimeTeardownService
    ) {
        self.plan = plan
        self.residence = residence
        self.terminalModel = terminalModel
        self.effect = effect
        guard terminalModel != nil else {
            physical = nil
            terminalDrain = nil
            return
        }
        if case .terminallyDrained = effect {
            physical = nil
        } else {
            physical = ShortcutLiveTabRetirementPhysicalEffect(
                prepared: ShortcutLiveRuntimeRetirementPreparedResultFactory
                    .make(plan: plan, effect: effect),
                teardown: teardown
            )
        }
        terminalDrain = { [teardown] in
            if case .committed(let committed) = effect {
                teardown.retirement.destroyAfterTerminalDrain(committed)
            }
        }
    }

    func canPublishNormally() -> Bool {
        guard terminalModel != nil else { return plan.tabs.isEmpty }
        if case .terminallyDrained = effect { return true }
        return physical != nil
    }

    func publish() -> PreparedShortcutLiveTabRetirement {
        guard isConsumed == false else {
            preconditionFailure("Shortcut retirement publication was consumed")
        }
        precondition(canPublishNormally())
        isConsumed = true
        let residencePublication = commitSilentResidence()
        let terminalEffect = terminalModel.map {
            PreparedShortcutLiveTabRetirementTerminalEffect(
                terminalModel: $0,
                residencePublication: residencePublication
            )
        }
        return ShortcutLiveRuntimeRetirementPreparedResultFactory.make(
            plan: plan, effect: effect, terminalEffect: terminalEffect
        )
    }

    func finishTerminalDrain() -> ShortcutLiveTerminalDrainEffect {
        guard isConsumed == false else {
            preconditionFailure("Shortcut retirement publication was consumed")
        }
        isConsumed = true
        let residencePublication = commitSilentResidence(
            physicalEffect: terminalDrain
        )
        return { [terminalModel] in
            residencePublication.publish()
            guard let terminalModel else { return }
            _ = terminalModel.publishLifecycle()
            _ = terminalModel.finishPhysicalEffect()
        }
    }

    private func commitSilentResidence(
        physicalEffect: ShortcutLiveTerminalDrainEffect? = nil
    ) -> PreparedShortcutLiveResidencePublication {
        guard let terminalModel else { return residence.commitSilentModel() }
        var publication: PreparedShortcutLiveResidencePublication?
        precondition(terminalModel.commitSilentModel {
            publication = residence.commitSilentModel()
        })
        let claimedEffect = physicalEffect ?? { [physical] in physical?.publish() }
        precondition(terminalModel.claimPhysicalEffect(preparing: {
            claimedEffect
        }) == .claimed)
        guard let publication else {
            preconditionFailure("Shortcut residence publication was not retained")
        }
        return publication
    }
}
