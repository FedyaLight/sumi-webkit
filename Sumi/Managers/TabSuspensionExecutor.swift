import Foundation
import WebKit

@MainActor
final class TabSuspensionExecutor {
    private let contextSource: TabSuspensionContextSource
    private let eligibilityEvaluator: TabSuspensionEligibilityEvaluator
    private let dateProvider: () -> Date
    private var runtime: TabSuspensionWebViewRuntime = .inactive

    init(
        contextSource: TabSuspensionContextSource,
        eligibilityEvaluator: TabSuspensionEligibilityEvaluator,
        dateProvider: @escaping () -> Date = Date.init
    ) {
        self.contextSource = contextSource
        self.eligibilityEvaluator = eligibilityEvaluator
        self.dateProvider = dateProvider
    }

    func attach(runtime: TabSuspensionWebViewRuntime) {
        self.runtime = runtime
    }

    func eligibility(
        for tab: Tab,
        context: TabSuspensionEvaluationContext
    ) -> TabSuspensionEligibility {
        if let ineligibility = eligibilityEvaluator.tabIneligibility(
            for: tab,
            context: context
        ) {
            return ineligibility
        }
        return eligibilityEvaluator.evaluateWebViews(
            liveWebViews: runtime.liveWebViews(tab),
            isProtectedFromCompositorMutation: runtime.isProtectedFromCompositorMutation
        )
    }

    func eligibility(
        for tab: Tab,
        webViewStates: [TabSuspensionWebViewState],
        context: TabSuspensionEvaluationContext
    ) -> TabSuspensionEligibility {
        eligibilityEvaluator.evaluate(
            tab: tab,
            webViewStates: webViewStates,
            context: context
        )
    }

    @discardableResult
    func suspend(_ tab: Tab, reason: String) -> Bool {
        suspend(tab, reason: reason, context: contextSource.context())
    }

    @discardableResult
    func suspend(
        _ tab: Tab,
        reason: String,
        context: TabSuspensionEvaluationContext
    ) -> Bool {
        guard eligibility(for: tab, context: context).isEligible else { return false }
        guard runtime.suspendWebViews(tab, reason) else { return false }

        tab.markSuspended(at: dateProvider())
        RuntimeDiagnostics.debug(category: "TabSuspension") {
            "suspended tab=\(tab.id.uuidString.prefix(8)) reason=\(reason)"
        }
        return true
    }
}

@MainActor
struct TabSuspensionCandidateRanker {
    private let executor: TabSuspensionExecutor

    init(executor: TabSuspensionExecutor) {
        self.executor = executor
    }

    func rankedTabs(
        from tabs: [Tab],
        inactiveBefore cutoffDate: Date? = nil,
        webViewStatesByTabID: [UUID: [TabSuspensionWebViewState]] = [:],
        context: TabSuspensionEvaluationContext
    ) -> [Tab] {
        tabs.compactMap { tab -> Tab? in
            let eligibility: TabSuspensionEligibility
            if let webViewStates = webViewStatesByTabID[tab.id] {
                eligibility = executor.eligibility(
                    for: tab,
                    webViewStates: webViewStates,
                    context: context
                )
            } else {
                eligibility = executor.eligibility(for: tab, context: context)
            }
            guard eligibility.isEligible else { return nil }
            if let cutoffDate,
               let lastSelectedAt = tab.lastSelectedAt,
               lastSelectedAt >= cutoffDate {
                return nil
            }
            return tab
        }
        .sorted { lhs, rhs in
            let leftDate = lhs.lastSelectedAt ?? .distantPast
            let rightDate = rhs.lastSelectedAt ?? .distantPast
            if leftDate != rightDate {
                return leftDate < rightDate
            }
            return lhs.id.uuidString < rhs.id.uuidString
        }
    }
}
