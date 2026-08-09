import Foundation
@testable import Sumi
import SumiWebRuntime

@MainActor
final class DeferredSpaceProfileTransition:
    TabWebViewRetirementParticipant,
    TabWebViewProfileTransitionParticipant {
    private let canRetireTabWebViews: ([Tab]) -> Bool
    private let beginCommittedTabRetirement: ([Tab]) -> Bool
    private let committedRetirementIsExactAction: ([Tab]) -> Bool
    private let destroyRetiredWebViews: ([RetiredTabWebViewGeneration]) -> Void
    private let destroyAfterTerminalDrain: (
        [RetiredTabWebViewGeneration],
        [Tab]
    ) -> Void
    private let unloadTab: (Tab) -> Void
    private var committedRetirementTabs: [UUID: Tab] = [:]
    private(set) var assignmentCount = 0
    private(set) var intent: DeferredWebViewSpaceProfileAssignmentIntent?
    private(set) var exactTabs: [Tab]?
    private(set) var validateModel: (@MainActor @Sendable () -> Bool)?
    private(set) var stageModel: (@MainActor @Sendable () -> Bool)?
    private(set) var finishModel: (() -> Void)?
    private(set) var stagedModelIsExact: (() -> Bool)?
    private(set) var canSealModel: (() -> Bool)?
    private(set) var sealModel: WebViewReplacementTerminalModelClaim?
    private(set) var publishCommit: (() -> Void)?
    private(set) var rollbackModel: (() -> Void)?
    private(set) var rollbackModelPublication: (() -> Void)?
    private(set) var settleTerminalModel: (() -> Void)?
    private(set) var settlement: ProfileTransitionService.Settlement?
    private(set) var tabIntent: DeferredWebViewProfileAssignmentIntent?
    private(set) var tabSettlement: ProfileTransitionService.Settlement?

    init(
        canRetireTabWebViews: @escaping ([Tab]) -> Bool = { _ in true },
        beginCommittedTabRetirement: @escaping ([Tab]) -> Bool = { _ in true },
        committedRetirementIsExact: @escaping ([Tab]) -> Bool = { _ in true },
        destroyRetiredWebViews: @escaping (
            [RetiredTabWebViewGeneration]
        ) -> Void = { _ in },
        destroyAfterTerminalDrain: @escaping (
            [RetiredTabWebViewGeneration],
            [Tab]
        ) -> Void = { _, _ in },
        unloadTab: @escaping (Tab) -> Void = { _ in }
    ) {
        self.canRetireTabWebViews = canRetireTabWebViews
        self.beginCommittedTabRetirement = beginCommittedTabRetirement
        committedRetirementIsExactAction = committedRetirementIsExact
        self.destroyRetiredWebViews = destroyRetiredWebViews
        self.destroyAfterTerminalDrain = destroyAfterTerminalDrain
        self.unloadTab = unloadTab
    }

    func makeLifecycle() -> TabManagerWebViewLifecycleService {
        TestRuntimePorts.webViewLifecycle(
            retirement: .rejecting,
            unloadTab: unloadTab,
            anyLiveWebView: { $0.resolvedCurrentWebView() },
            retirementParticipant: self,
            profileTransitions: self
        )
    }

    func canRetire(_ tabs: [Tab]) -> Bool {
        canRetireTabWebViews(tabs)
    }

    func prepareRetirementOwners(_ tabs: [Tab]) {}

    func beginCommittedRetirement(_ tabs: [Tab]) -> Bool {
        guard beginCommittedTabRetirement(tabs) else { return false }
        committedRetirementTabs = Dictionary(
            uniqueKeysWithValues: tabs.map { ($0.id, $0) }
        )
        return true
    }

    func committedRetirementIsExact(_ tabs: [Tab]) -> Bool {
        committedRetirementIsExactAction(tabs)
            && committedRetirementTabs.count == tabs.count
            && tabs.allSatisfy { committedRetirementTabs[$0.id] === $0 }
    }

    func destroyRetiredGenerations(
        _ generations: [RetiredTabWebViewGeneration],
        completing tabs: [Tab]
    ) {
        destroyRetiredWebViews(generations)
        committedRetirementTabs.removeAll()
    }

    func destroyTerminallyDrainedGenerations(
        _ generations: [RetiredTabWebViewGeneration],
        belongingTo tabs: [Tab]
    ) {
        destroyAfterTerminalDrain(generations, tabs)
        committedRetirementTabs.removeAll()
    }

    func abortProfileTransitions(profileIDs: Set<UUID>) -> Int { 0 }

    func executePreparedProfileAssignments(
        _ assignments: [PreparedTabProfileAssignment],
        bindingModel: any ShortcutTabBindingAggregateTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> PreparedProfileAssignmentBatchTransitionOutcome {
        let model = PreparedProfileAssignmentBatchModelTransaction(
            assignments: assignments,
            binding: bindingModel
        )
        guard model.validateForStaging() else {
            return .rejectedUnstaged(.stale)
        }
        let outcome = ProfileTransitionModelOnlySettlement.execute(
            .transaction(model)
        )
        settlement(outcome.settlement)
        return outcome.batchExecution
    }

    func executeProfileAssignment(
        for tab: Tab,
        targetProfile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        tabIntent = intent
        tabSettlement = settlement
        return .deferred
    }

    func executeSpaceProfileAssignment(
        space: Space,
        targetProfile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        model: any SpaceProfileWebViewReplacementTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        assignmentCount += 1
        self.intent = intent
        exactTabs = model.exactTabsForRuntime()
        validateModel = { model.validateForStaging() }
        stageModel = {
            do {
                try model.stage()
                return true
            } catch {
                return false
            }
        }
        stagedModelIsExact = model.stagedModelIsExact
        canSealModel = model.canClaimTerminalModel
        sealModel = model.claimTerminalModel
        publishCommit = model.publishCommit
        finishModel = {
            precondition(model.stagedModelIsExact())
            precondition(model.canClaimTerminalModel())
            precondition(model.claimTerminalModel() == .sealed)
            model.publishCommit()
        }
        rollbackModel = { try? model.rollback() }
        rollbackModelPublication = model.publishRollback
        settleTerminalModel = { _ = model.settleTerminalDrain() }
        self.settlement = settlement
        return .deferred
    }
}
