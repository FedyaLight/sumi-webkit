import Foundation
import SumiWebRuntime
import WebKit

enum WebViewDetachedReplacementCommitOutcome: Equatable {
    /// The replacement generation is canonical and the retired generation was
    /// handed to the shared replacement pipeline for physical cleanup.
    case committed
    /// Admission never began; the caller still owns the replacement WebView.
    case rejected
    /// Admission began but settlement failed. The pipeline owns cleanup of the
    /// replacement generation, so the caller must not destroy it again.
    case consumedByFailedTransaction
}

/// Replaces a complete parked/untracked generation through the shared
/// ownership transaction and cleanup settlement pipeline.
@MainActor
final class DetachedWebViewReplacementService {
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let webViewSessions: WebViewSessionRepository
    private let pipeline: WebViewReplacementPipeline

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        webViewSessions: WebViewSessionRepository,
        pipeline: WebViewReplacementPipeline
    ) {
        self.runtimeTabs = runtimeTabs
        self.webViewSessions = webViewSessions
        self.pipeline = pipeline
    }

    func replace(
        _ previous: WKWebView,
        with replacement: WKWebView,
        for tab: Tab
    ) -> WebViewDetachedReplacementCommitOutcome {
        guard runtimeTabs.bind(tab).isAccepted else { return .rejected }
        tab.webViewSession.requireBacking(by: webViewSessions)
        let snapshot = webViewSessions.snapshot(for: tab.id)
        guard snapshot.windowWebViews.isEmpty else { return .rejected }

        let residence: WebViewDetachedReplacementResidence
        if snapshot.untrackedWebView === previous {
            residence = .untracked
        } else if snapshot.parkedWebView === previous,
                  snapshot.untrackedWebView == nil {
            residence = .parked
        } else {
            return .rejected
        }

        let policyChangeSet = tab.preparedConfigurationPolicyChangeSet(
            for: [replacement]
        )
        if replacement.configuration.sumiIsNormalTabWebViewConfiguration {
            guard policyChangeSet != nil else { return .rejected }
        } else if replacement.sumiPreparedConfigurationPolicyChange != nil {
            policyChangeSet?.cancel()
            return .rejected
        }
        guard let prepared = PreparedWebViewReplacement(
            tab: tab,
            snapshot: snapshot,
            placement: .detached(
                webView: replacement,
                residence: residence
            ),
            replacements: [replacement],
            trackedReplacements: [],
            bindingReplacements: [],
            targetURL: tab.url,
            semanticRevision: tab.mainFrameLoads.currentIntent.revision,
            profileID: tab.resolveProfile()?.id ?? tab.profileId,
            requiresExtensionRuntimePreparation: false,
            configurationPolicyChangeSet: policyChangeSet
        ) else {
            policyChangeSet?.cancel()
            return .rejected
        }

        let start = pipeline.begin(
            [prepared],
            profileIDs: Set([prepared.profileID].compactMap { $0 }),
            validateModel: {
                let current = self.webViewSessions.snapshot(for: tab.id)
                return current.generation == snapshot.generation
                    && current.windowWebViews.isEmpty
                    && (
                        residence == .untracked
                            ? current.untrackedWebView === previous
                            : current.parkedWebView === previous
                                && current.untrackedWebView == nil
                    )
            },
            modelCommit: {},
            modelRollback: {},
            completion: { _ in }
        )

        switch start {
        case .committed:
            return .committed
        case .stale, .conflict, .invalid, .modelCommitFailed:
            return .rejected
        case .rolledBack, .settlementConflict, .leaseLost:
            return .consumedByFailedTransaction
        case .started:
            preconditionFailure(
                "Detached replacement without navigation bindings must settle synchronously"
            )
        }
    }
}
