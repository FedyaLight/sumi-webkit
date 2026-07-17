@MainActor
private final class ShortcutLiveTerminalDrainPublication {
    private let retirement: TabRuntimeRetirementService
    private let ownership: CommittedTabRuntimeRetirementCleanupOwnership?

    init(
        retirement: TabRuntimeRetirementService,
        ownership: CommittedTabRuntimeRetirementCleanupOwnership?
    ) {
        self.retirement = retirement
        self.ownership = ownership
    }

    func publish() {
        guard let ownership else { return }
        retirement.destroyAfterTerminalDrain(ownership)
    }
}

@MainActor
private struct ShortcutLiveRuntimeRetirementPublicationEffects {
    let claimed: ShortcutLiveRuntimeRetirementEffect
    let physical: ShortcutLiveTabRetirementPhysicalEffect?
    let terminalDrain: ShortcutLiveTerminalDrainPublication?

    init(
        plan: ShortcutLiveTabRetirementPlan,
        claimed: ShortcutLiveRuntimeRetirementEffect,
        hasTerminalModel: Bool,
        teardown: TabRuntimeTeardownService
    ) {
        self.claimed = claimed
        guard hasTerminalModel else {
            physical = nil
            terminalDrain = nil
            return
        }
        if case .terminallyDrained = claimed {
            physical = nil
        } else {
            physical = ShortcutLiveTabRetirementPhysicalEffect(
                prepared: ShortcutLiveRuntimeRetirementPreparedResultFactory
                    .make(plan: plan, effect: claimed),
                teardown: teardown
            )
        }
        let ownership: CommittedTabRuntimeRetirementCleanupOwnership?
        if case .committed(let committed) = claimed {
            ownership = committed
        } else {
            ownership = nil
        }
        terminalDrain = ShortcutLiveTerminalDrainPublication(
            retirement: teardown.retirement,
            ownership: ownership
        )
    }
}

@MainActor
final class ShortcutLiveRuntimeRetirementPublication {
    private let plan: ShortcutLiveTabRetirementPlan
    private let residence: ShortcutLiveResidenceRetirementParticipant
    private let terminalModel: PreparedTabTerminalModelRetirement?
    private let effects: ShortcutLiveRuntimeRetirementPublicationEffects
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
        effects = ShortcutLiveRuntimeRetirementPublicationEffects(
            plan: plan,
            claimed: effect,
            hasTerminalModel: terminalModel != nil,
            teardown: teardown
        )
    }

    func canPublishNormally() -> Bool {
        guard terminalModel != nil else { return plan.tabs.isEmpty }
        if case .terminallyDrained = effects.claimed { return true }
        return effects.physical != nil
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
            plan: plan,
            effect: effects.claimed,
            terminalEffect: terminalEffect
        )
    }

    func finishTerminalDrain() -> ShortcutLiveTerminalDrainEffect {
        guard isConsumed == false else {
            preconditionFailure("Shortcut retirement publication was consumed")
        }
        isConsumed = true
        let residencePublication = commitSilentResidence(
            physicalEffect: { [terminalDrain = effects.terminalDrain] in
                terminalDrain?.publish()
            }
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
        let claimedEffect = physicalEffect
            ?? { [physical = effects.physical] in physical?.publish() }
        precondition(terminalModel.claimPhysicalEffect(preparing: {
            claimedEffect
        }) == .claimed)
        guard let publication else {
            preconditionFailure("Shortcut residence publication was not retained")
        }
        return publication
    }
}
