import Foundation
import SumiWebRuntime
import WebKit

enum TabWebViewReplacementOutcome: Equatable {
    case notNeeded
    case replacedNavigationPending
    case replacedAndScheduledNavigation
    case deferred
    case failed

    var didReplace: Bool {
        self == .replacedNavigationPending
            || self == .replacedAndScheduledNavigation
    }

    var navigationWasScheduled: Bool {
        self == .replacedAndScheduledNavigation
    }

    var blocksCallerNavigation: Bool {
        self == .deferred || self == .failed
    }
}

/// Performs one exact configuration-driven replacement against a concrete
/// Tab. Whole tracked generations stay in the shared replacement pipeline;
/// detached generations use the same canonical transaction through the Tab's
/// installed WebView runtime.
@MainActor
struct TabWebViewReplacementService {
    @discardableResult
    func replaceNormalWebView(
        in tab: Tab,
        targetURL: URL,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        replaceCurrentWebView(
            in: tab,
            targetURL: targetURL,
            reason: reason,
            configuration: .normal,
            makeReplacementWebView: { reason in
                tab.makeNormalTabWebView(reason: reason)
            }
        )
    }

    @discardableResult
    func replaceCurrentWebView(
        in tab: Tab,
        targetURL: URL,
        reason: String,
        configuration: DeferredWebViewRebuildConfiguration,
        makeReplacementWebView: (String) -> WKWebView?
    ) -> TabWebViewReplacementOutcome {
        guard let previousWebView = tab.resolvedCurrentWebView() else {
            return .notNeeded
        }

        if let primaryWindowID = tab.resolvedPrimaryWindowId() {
            switch tab.navigationRuntime.webViewReplacementRuntime
                .rebuildTrackedWebViews(
                    tab,
                    primaryWindowID,
                    targetURL,
                    reason,
                    configuration
                ) {
            case .committed:
                return .replacedAndScheduledNavigation
            case .deferred:
                return .deferred
            case .noLiveWindows, .failed:
                return .failed
            }
        }

        guard let replacementWebView = makeReplacementWebView(reason) else {
            return .failed
        }

        switch tab.navigationRuntime.webViewReplacementRuntime
            .commitUntrackedReplacement(
                tab,
                previousWebView,
                replacementWebView
            ) {
        case .committed:
            tab.invalidatePermissionPageForReplacement(reason: reason)
            return .replacedNavigationPending
        case .rejected:
            tab.cleanupCloneWebView(replacementWebView)
            return .failed
        case .consumedByFailedTransaction:
            return .failed
        }
    }
}
