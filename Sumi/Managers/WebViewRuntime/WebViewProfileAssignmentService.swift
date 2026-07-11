import Foundation
import SumiWebRuntime

/// Bridges model profile assignments to the atomic WebView replacement
/// transaction. It resolves the exact live tab set, rejects stale intents, and
/// keeps model commit/rollback coupled to runtime settlement.
@MainActor
final class WebViewProfileAssignmentService {
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let resolveRuntimeTab: @MainActor (UUID) -> Tab?
    private let transitions: ProfileTransitionService
    private let replacementPipeline: WebViewReplacementPipeline

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        resolveRuntimeTab: @escaping @MainActor (UUID) -> Tab?,
        transitions: ProfileTransitionService,
        replacementPipeline: WebViewReplacementPipeline
    ) {
        self.runtimeTabs = runtimeTabs
        self.resolveRuntimeTab = resolveRuntimeTab
        self.transitions = transitions
        self.replacementPipeline = replacementPipeline
    }

    func executeSpaceProfileAssignment(
        space: Space,
        targetProfile: Profile,
        intent: DeferredWebViewSpaceProfileAssignmentIntent,
        validateModel: @escaping @MainActor @Sendable () -> Bool,
        modelCommit: @escaping @MainActor @Sendable () -> Bool,
        modelFinish: @escaping () -> Void = {},
        modelRollback: @escaping () -> Void,
        settlement: @escaping ProfileTransitionService.Settlement = { _ in }
    ) -> TabProfileAssignmentExecutionOutcome {
        let tabs = intent.tabIntents.compactMap { tabIntent in
            runtimeTabs.resolve(
                tabIntent.tabID,
                resolveRuntimeTab: resolveRuntimeTab
            )
        }
        guard tabs.count == intent.tabIntents.count else {
            settlement(.rejected(.stale))
            return .stale
        }

        tabs.forEach(runtimeTabs.bind)
        return transitions.transition(
            spaceID: space.id,
            to: targetProfile,
            intent: intent,
            tabsByID: Dictionary(
                uniqueKeysWithValues: tabs.map { ($0.id, $0) }
            ),
            validateModel: validateModel,
            stageModel: modelCommit,
            finishModel: modelFinish,
            rollbackModel: modelRollback,
            settlement: settlement
        )
    }

    func executeProfileAssignment(
        for tab: Tab,
        targetProfile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent,
        settlement: @escaping ProfileTransitionService.Settlement = { _ in }
    ) -> TabProfileAssignmentExecutionOutcome {
        runtimeTabs.bind(tab)
        return transitions.transition(
            tab: tab,
            to: targetProfile,
            intent: intent,
            settlement: settlement
        )
    }

    @discardableResult
    func abortProfileTransitions(profileIDs: Set<UUID>) -> Int {
        replacementPipeline.abort(
            profileIDs: profileIDs,
            reason: .profileTransition
        )
    }
}
