import Foundation

@MainActor
final class ShortcutLiveRetirementBatchTransaction {
    private let plans: ShortcutLiveRetirementBatchPlanFactory
    private let structuralLookup: TabStructuralLookupCoordinator
    private let windowMutations: BrowserWindowShortcutMutationOwner
    private let teardown: TabRuntimeTeardownService

    init(
        registry: LiveShortcutTabRegistry,
        structuralLookup: TabStructuralLookupCoordinator,
        runtimeConnection: TabRuntimePortConnection,
        windowMutations: BrowserWindowShortcutMutationOwner,
        splitGroups: SplitGroupStore,
        splitMutations: SplitGroupMutationService,
        teardown: TabRuntimeTeardownService
    ) {
        plans = ShortcutLiveRetirementBatchPlanFactory(
            registry: registry,
            connection: runtimeConnection,
            splitPlanner: ShortcutLiveRetirementSplitPlanner(
                store: splitGroups,
                mutations: splitMutations
            )
        )
        self.structuralLookup = structuralLookup
        self.windowMutations = windowMutations
        self.teardown = teardown
    }

    func prepareWindowRetirement(
        pinIDs: Set<UUID>,
        in windowID: UUID,
        targetWindowState: BrowserWindowShortcutMutationState? = nil
    ) -> ShortcutLiveRetirementBatchPreparation {
        guard pinIDs.isEmpty == false else { return .noEffect }
        guard let plan = plans.windowRetirement(
            pinIDs: pinIDs,
            windowID: windowID,
            targetWindowState: targetWindowState
        ) else { return .rejected }
        guard plan.entries.isEmpty == false else { return .noEffect }
        return commit(plan)
    }

    func prepareDeletedPins(
        _ pinIDs: Set<UUID>,
        targetWindowStates: [UUID: BrowserWindowShortcutMutationState] = [:]
    ) -> ShortcutLiveRetirementBatchPreparation {
        guard pinIDs.isEmpty == false else { return .noEffect }
        guard let plan = plans.deletedPins(
            pinIDs,
            targetWindowStates: targetWindowStates
        ) else { return .rejected }
        if plan.hasModelEffect == false { return .noEffect }
        return commit(plan)
    }

    private func commit(
        _ plan: ShortcutLiveRetirementBatchPlan
    ) -> ShortcutLiveRetirementBatchPreparation {
        guard let model = ShortcutLiveRetirementBatchModelParticipant(
            plan: plan,
            windowMutations: windowMutations,
            teardown: teardown
        ) else { return .rejected }
        let runtime = ShortcutLiveRetirementBatchRuntimeParticipant(
            plan: plan,
            model: model,
            retirement: teardown.retirement
        )
        switch runtime.stage() {
        case .staged:
            break
        case .cleanup(let ownership, _):
            structuralLookup.runAfterCurrentBatch {
                self.teardown.retirement
                    .destroyAfterTerminalDrain(ownership)
            }
            return .rejected
        case .rejected:
            return .rejected
        }
        let claimed: ShortcutLiveRetirementBatchRuntimeParticipant.ClaimedEffect
        switch runtime.claim() {
        case .claimed(let effect):
            claimed = effect
        case .cleanup(let ownership, _):
            structuralLookup.runAfterCurrentBatch {
                self.teardown.retirement
                    .destroyAfterTerminalDrain(ownership)
            }
            return .rejected
        case .rejected:
            return .rejected
        }
        let physical = ShortcutLiveRetirementBatchPhysicalEffect(
            plan: plan,
            effect: claimed,
            retirement: teardown.retirement
        )
        let residence = model.commitSilentModel()
        let terminal = ShortcutLiveRetirementBatchTerminalEffect(
            terminalModel: model.terminalReceipt,
            residence: residence,
            physical: physical
        )
        runtime.markTerminal()
        terminal.queueResidencePublication()
        structuralLookup.runBeforeCurrentBatchPublication {
            model.publishWindows()
        }
        return .prepared(PreparedShortcutLiveRetirementBatch(
            result: plan.result,
            terminalEffect: terminal
        ))
    }
}
