import SumiWebRuntime

@MainActor
final class ShortcutLiveRuntimeRetirementParticipant {
    enum BeginOutcome { case staged, restored, cleanupRetained, conflicted }
    enum SealOutcome { case claimed, restored, cleanupRetained, conflicted }

    private enum State {
        case prepared
        case staged(ShortcutLiveRuntimeRetirementStage)
        case claimed(ShortcutLiveRuntimeRetirementEffect)
        case retainedDrain(ShortcutLiveRuntimeRetirementDrain)
        case restoredAfterFailedClaim
        case terminal, conflicted
    }

    private let plan: ShortcutLiveTabRetirementPlan
    private let staging: ShortcutLiveRuntimeRetirementStaging
    private var publication: ShortcutLiveRuntimeRetirementPublication?
    private var state = State.prepared

    init?(
        plan: ShortcutLiveTabRetirementPlan,
        residence: ShortcutLiveResidenceRetirementParticipant,
        teardown: TabRuntimeTeardownService
    ) {
        self.plan = plan
        guard let staging = ShortcutLiveRuntimeRetirementStaging(
            plan: plan, residence: residence, teardown: teardown
        ) else { return nil }
        self.staging = staging
    }

    func stage() -> BeginOutcome {
        guard case .prepared = state else { return .conflicted }
        switch staging.stage() {
        case .staged(let stage):
            state = .staged(stage)
            return stagedModelIsExact(windowState: plan.sourceWindowState)
                ? .staged : .conflicted
        case .terminal:
            state = .terminal
            return .restored
        case .cleanup(let drain):
            state = .retainedDrain(drain)
            return .cleanupRetained
        case .conflicted:
            state = .conflicted
            return .conflicted
        }
    }

    func stagedModelIsExact(
        windowState: BrowserWindowShortcutMutationState?
    ) -> Bool {
        guard case .staged(let stage) = state else { return false }
        return staging.stagedModelIsExact(stage, windowState: windowState)
    }

    func claim(
        windowState: BrowserWindowShortcutMutationState?
    ) -> SealOutcome {
        guard case .staged(let stage) = state else { return .conflicted }
        switch staging.claim(stage, windowState: windowState) {
        case .claimed(let effect, let publication):
            state = .claimed(effect)
            self.publication = publication
            return .claimed
        case .cleanup(let drain):
            state = .retainedDrain(drain)
            return .cleanupRetained
        case .restored:
            state = .restoredAfterFailedClaim
            return .restored
        case .conflict:
            state = .conflicted
            return .conflicted
        }
    }

    func claimedModelIsExact(
        windowState: BrowserWindowShortcutMutationState?
    ) -> Bool {
        guard case .claimed(let effect) = state else { return false }
        return staging.claimedModelIsExact(effect, windowState: windowState)
    }

    func canAbandonClaimedEffect(
        windowState: BrowserWindowShortcutMutationState?
    ) -> Bool {
        switch state {
        case .claimed(let effect):
            return staging.canAbandon(effect, windowState: windowState)
        case .retainedDrain, .restoredAfterFailedClaim:
            return true
        case .prepared, .staged, .terminal, .conflicted:
            return false
        }
    }

    func rollback() -> Bool {
        guard case .staged(let stage) = state else { return false }
        let restored = staging.rollback(stage)
        state = restored ? .terminal : .conflicted
        return restored
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        let cancelled = staging.cancelPrepared()
        state = cancelled ? .terminal : .conflicted
        return cancelled
    }

    func settleAfterFailedStage() -> Bool {
        switch state {
        case .prepared: return cancelPrepared()
        case .terminal: return true
        case .retainedDrain: return true
        case .staged, .claimed, .restoredAfterFailedClaim, .conflicted:
            return false
        }
    }

    func publish() -> PreparedShortcutLiveTabRetirement {
        guard case .claimed = state, let publication else {
            preconditionFailure("Shortcut runtime retirement was not claimed")
        }
        state = .terminal
        return publication.publish()
    }

    func finishTerminalDrain() -> ShortcutLiveTerminalDrainEffect {
        let effect: ShortcutLiveTerminalDrainEffect
        switch state {
        case .claimed:
            guard let publication else {
                preconditionFailure("Shortcut runtime publication was not retained")
            }
            effect = publication.finishTerminalDrain()
        case .retainedDrain(let drain):
            effect = drain.finish()
        case .restoredAfterFailedClaim:
            effect = {}
        case .prepared, .staged, .terminal, .conflicted:
            preconditionFailure("Shortcut runtime retirement cannot drain")
        }
        state = .terminal
        return effect
    }
}
