import Foundation
import SumiWebRuntime

/// Bridges model profile assignments to the atomic WebView replacement
/// transaction. It resolves the exact live tab set, rejects stale intents, and
/// keeps model commit/rollback coupled to runtime settlement.
@MainActor
final class WebViewProfileAssignmentService:
    TabWebViewProfileTransitionParticipant {
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
        model: any SpaceProfileWebViewReplacementTransaction,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        guard let tabs = model.exactTabsForRuntime(),
              tabs.count == intent.tabIntents.count,
              zip(tabs, intent.tabIntents).allSatisfy({ tab, tabIntent in
                  tab.id == tabIntent.tabID
              }),
              tabs.allSatisfy({ resolveRuntimeTab($0.id) === $0 }),
              runtimeTabs.bindAtomically(tabs) else {
            settlement(.rejected(.stale))
            return .stale
        }

        return transitions.transition(
            spaceID: space.id,
            to: targetProfile,
            intent: intent,
            tabsByID: Dictionary(
                uniqueKeysWithValues: tabs.map { ($0.id, $0) }
            ),
            model: model,
            settlement: settlement
        )
    }

    func executeProfileAssignment(
        for tab: Tab,
        targetProfile: Profile,
        intent: DeferredWebViewProfileAssignmentIntent,
        settlement: @escaping ProfileTransitionService.Settlement
    ) -> TabProfileAssignmentExecutionOutcome {
        guard runtimeTabs.bind(tab).isAccepted else {
            settlement(.rejected(.stale))
            return .stale
        }
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
