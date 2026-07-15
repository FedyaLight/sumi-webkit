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
    private let residences: WindowSplitPresentationResidenceTransaction
    private let validator: WindowSplitPresentationSettlementValidator
    private let terminalEffects:
        WindowSplitPresentationEffectExecutor
    private let terminalParticipants:
        WindowSplitPresentationTerminalParticipants
    private var aggregateWindowStates: [
        UUID: BrowserWindowShortcutMutationState
    ]?
    private var state = State.prepared

    init(
        plan: WindowSplitPresentationSettlementPlan,
        residences: WindowSplitPresentationResidenceTransaction,
        validator: WindowSplitPresentationSettlementValidator,
        terminalEffects: WindowSplitPresentationEffectExecutor,
        terminalParticipants: WindowSplitPresentationTerminalParticipants
    ) {
        self.plan = plan
        self.residences = residences
        self.validator = validator
        self.terminalEffects = terminalEffects
        self.terminalParticipants = terminalParticipants
    }

    func stage() -> Bool {
        guard case .prepared = state,
              validator.canStage(plan),
              residences.stagePrepared() else { return false }
        state = .staged
        guard isCurrentForWindowSettlement() else {
            residences.rollback()
            state = .rolledBack
            return false
        }
        return true
    }

    var windowContribution: ShortcutTabBindingWindowContribution {
        ShortcutTabBindingWindowContribution(entries: plan.windows.map {
            .init(
                window: $0.window,
                source: $0.expectedWindowState,
                target: $0.targetWindowState,
                requiresPersistence: false
            )
        })
    }

    func admitAggregateWindowStates(
        _ states: [UUID: BrowserWindowShortcutMutationState]
    ) -> Bool {
        guard case .prepared = state,
              aggregateWindowStates == nil,
              plan.windows.allSatisfy({ states[$0.window.id] != nil })
        else { return false }
        aggregateWindowStates = states
        return true
    }

    func admitCatalogIdentityHandoff(
        _ handoff: ShortcutPresentationCatalogIdentityHandoff
    ) -> Bool {
        guard case .prepared = state else { return false }
        return residences.admitCatalogIdentityHandoff(handoff)
    }

    func cancelPrepared() -> Bool {
        guard case .prepared = state else { return false }
        state = .rolledBack
        return true
    }

    func settleAfterFailedStage() -> Bool {
        switch state {
        case .prepared: return cancelPrepared()
        case .rolledBack: return true
        case .staged, .windowSettled, .published, .effectsPublished:
            return false
        }
    }

    func acceptAggregateWindowSettlement() -> Bool {
        guard case .staged = state,
              let aggregateWindowStates,
              residences.acceptBoundIdentity(),
              validator.modelIsCurrent(
                  plan,
                  expectedWindowStates: aggregateWindowStates
              ) else { return false }
        state = .windowSettled
        return true
    }

    func aggregateWindowModelIsExact() -> Bool {
        guard case .windowSettled = state,
              let aggregateWindowStates else { return false }
        return residences.canPublish() && validator.modelIsCurrent(
            plan,
            expectedWindowStates: aggregateWindowStates
        )
    }

    func isCurrentForWindowSettlement() -> Bool {
        guard case .staged = state,
              residences.preparedIdentityIsExact() else { return false }
        return validator.preparedModelIsCurrent(plan)
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
        residences.publish()
    }

    func rollback() {
        switch state {
        case .staged, .windowSettled:
            break
        case .prepared, .published, .rolledBack, .effectsPublished:
            return
        }
        residences.rollback()
        state = .rolledBack
    }

    func canAbandonForTerminalDrain() -> Bool {
        switch state {
        case .rolledBack, .effectsPublished: return true
        case .windowSettled: return aggregateWindowModelIsExact()
        case .prepared, .staged, .published: return false
        }
    }

    func abandonForTerminalDrain() {
        precondition(canAbandonForTerminalDrain())
        if case .rolledBack = state { return }
        if case .effectsPublished = state { return }
        residences.abandonForTerminalDrain()
        state = .effectsPublished
    }

    func canForfeitPreservingCurrent() -> Bool {
        switch state {
        case .staged, .windowSettled: return true
        case .prepared, .published, .rolledBack, .effectsPublished: return false
        }
    }

    func forfeitPreservingCurrent() {
        precondition(canForfeitPreservingCurrent())
        residences.forfeitPreservingCurrent()
        state = .effectsPublished
    }

    func publishTerminalEffects() {
        guard case .published = state else { return }
        state = .effectsPublished
        terminalEffects.publishTerminalEffects(
            witness: WindowSplitPresentationTerminalWitness(
                plan: plan,
                residences: residences,
                validator: validator,
                windowStates: aggregateWindowStates
                    ?? Dictionary(uniqueKeysWithValues: plan.windows.map {
                        ($0.window.id, $0.targetWindowState)
                    })
            ),
            participants: terminalParticipants
        )
    }
}
