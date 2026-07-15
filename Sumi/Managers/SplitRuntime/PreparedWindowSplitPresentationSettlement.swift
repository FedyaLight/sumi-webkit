/// Single-use model receipt for one immutable split-presentation plan. It owns
/// only transaction phase, exact-current validation and the prepared shortcut
/// activation; planning and outward effects are separate collaborators.
@MainActor
final class PreparedWindowSplitPresentationSettlement:
    BrowserWindowShortcutAggregateParticipant {
    private enum State {
        case prepared
        case staged
        case windowSettled
        case published
        case rolledBack
        case effectsPublished
    }

    private let plan: WindowSplitPresentationSettlementPlan
    private let activation: ShortcutPresentationActivationReceipt
    private let validator: WindowSplitPresentationSettlementValidator
    private let terminalEffects:
        WindowSplitPresentationEffectExecutor
    private let terminalParticipants:
        WindowSplitPresentationTerminalParticipants
    private var state = State.prepared

    init(
        plan: WindowSplitPresentationSettlementPlan,
        activation: ShortcutPresentationActivationReceipt,
        validator: WindowSplitPresentationSettlementValidator,
        terminalEffects: WindowSplitPresentationEffectExecutor,
        terminalParticipants: WindowSplitPresentationTerminalParticipants
    ) {
        self.plan = plan
        self.activation = activation
        self.validator = validator
        self.terminalEffects = terminalEffects
        self.terminalParticipants = terminalParticipants
    }

    func stage() -> Bool {
        guard case .prepared = state,
              validator.canStage(plan),
              activation.stage() else { return false }
        state = .staged
        guard isCurrentForWindowSettlement() else {
            activation.rollback()
            state = .rolledBack
            return false
        }
        return true
    }

    func isCurrentForWindowSettlement() -> Bool {
        guard case .staged = state,
              activation.canPublish() else { return false }
        return validator.isCurrentForWindowSettlement(plan)
    }

    func settleAdmittedWindowModel(
        using owner: BrowserWindowShortcutMutationOwner
    ) {
        guard isCurrentForWindowSettlement() else {
            preconditionFailure("Split presentation was not admitted")
        }
        for windowPlan in plan.windows {
            owner.stage(windowPlan.window) {
                $0 = windowPlan.targetWindowState
            }
        }
        state = .windowSettled
    }

    func publishAdmittedModel() {
        guard case .windowSettled = state else {
            preconditionFailure(
                "Split presentation window model was not settled"
            )
        }
        state = .published
        activation.publish()
    }

    func rollback() {
        guard case .staged = state else { return }
        activation.rollback()
        state = .rolledBack
    }

    func publishTerminalEffects() {
        guard case .published = state else { return }
        state = .effectsPublished
        terminalEffects.publishTerminalEffects(
            for: plan,
            validator: validator,
            participants: terminalParticipants
        )
    }
}
