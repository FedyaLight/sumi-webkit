import Foundation

typealias ShortcutLiveTerminalDrainEffect = @MainActor () -> Void

@MainActor
final class ReversibleShortcutLiveTabRetirement {
    enum BeginOutcome { case staged, restored, cleanupRetained, conflicted }
    enum SealOutcome { case claimed, restored, cleanupRetained, conflicted }

    private let plan: ShortcutLiveTabRetirementPlan
    private let runtime: ShortcutLiveRuntimeRetirementParticipant
    private var aggregateWindowState: BrowserWindowShortcutMutationState?
    private var preparedResult: PreparedShortcutLiveTabRetirement?

    init?(
        pinID: UUID,
        windowID: UUID,
        registry: LiveShortcutTabRegistry,
        runtimeConnection: TabRuntimePortConnection,
        runtimeTeardown: TabRuntimeTeardownService
    ) {
        guard let plan = ShortcutLiveTabRetirementPlan(
            pinID: pinID,
            windowID: windowID,
            registry: registry,
            runtimeConnection: runtimeConnection
        ) else { return nil }
        let residence = ShortcutLiveResidenceRetirementParticipant(plan: plan)
        self.plan = plan
        guard let runtime = ShortcutLiveRuntimeRetirementParticipant(
            plan: plan, residence: residence, teardown: runtimeTeardown
        ) else { return nil }
        self.runtime = runtime
    }

    func windowContribution(
        reconcilingWith presentation: ShortcutTabBindingWindowContribution
    ) -> ShortcutTabBindingWindowContribution? {
        guard let (contribution, target) = plan.windowContribution(
            reconcilingWith: presentation
        ) else { return nil }
        aggregateWindowState = target
        return contribution
    }

    var bindingExclusion: ShortcutLiveRetirementBindingExclusion? {
        plan.bindingExclusion
    }

    func begin() -> BeginOutcome {
        switch runtime.stage() {
        case .staged: return .staged
        case .restored: return .restored
        case .cleanupRetained: return .cleanupRetained
        case .conflicted: return .conflicted
        }
    }

    func aggregateModelIsExact() -> Bool {
        runtime.stagedModelIsExact(windowState: aggregateWindowState)
    }

    func sealRuntime() -> SealOutcome {
        switch runtime.claim(windowState: aggregateWindowState) {
        case .claimed: return .claimed
        case .restored: return .restored
        case .cleanupRetained: return .cleanupRetained
        case .conflicted: return .conflicted
        }
    }

    func claimedAggregateModelIsExact() -> Bool {
        runtime.claimedModelIsExact(windowState: aggregateWindowState)
    }

    func acceptAggregateWindowSettlement() -> Bool {
        claimedAggregateModelIsExact()
    }

    func rollback() -> Bool { runtime.rollback() }

    func cancelPrepared() -> Bool { runtime.cancelPrepared() }

    func settleAfterFailedBegin() -> Bool {
        runtime.settleAfterFailedStage()
    }

    func publishAdmittedModel() {
        guard preparedResult == nil else {
            preconditionFailure("Shortcut retirement published twice")
        }
        preparedResult = runtime.publish()
    }

    func takePreparedResult() -> PreparedShortcutLiveTabRetirement {
        guard let preparedResult else {
            preconditionFailure("Shortcut retirement was not published")
        }
        self.preparedResult = nil
        return preparedResult
    }

    func canAbandonForTerminalDrain() -> Bool {
        runtime.canAbandonClaimedEffect(windowState: aggregateWindowState)
    }

    func finishTerminalDrain() -> ShortcutLiveTerminalDrainEffect {
        precondition(canAbandonForTerminalDrain())
        return runtime.finishTerminalDrain()
    }
}
