import Foundation
import SumiWebRuntime
import WebKit

enum TabWebViewReplacementOutcome: Equatable {
    /// No configuration replacement was required; the caller owns navigation.
    case notNeeded
    /// A detached WebView was atomically replaced; the caller must navigate it.
    case replacedNavigationPending
    /// A tracked window set was committed and navigation was scheduled for all replacements.
    case replacedAndScheduledNavigation
    /// The semantic replacement was queued behind compositor protection.
    case deferred
    /// The requested replacement could not be created or committed.
    case failed

    var didReplace: Bool {
        self == .replacedNavigationPending || self == .replacedAndScheduledNavigation
    }

    var navigationWasScheduled: Bool {
        self == .replacedAndScheduledNavigation
    }

    var blocksCallerNavigation: Bool {
        self == .deferred || self == .failed
    }
}

@MainActor
struct TabWebViewReplacementContext {
    let existingWebView: () -> WKWebView?
    let hasTrackedWebViews: () -> Bool
    let rebuildTrackedWebViews: (
        _ targetURL: URL,
        _ reason: String,
        _ configuration: DeferredWebViewRebuildConfiguration
    ) -> TabWebViewRebuildResult
    let makeNormalTabWebView: (String) -> WKWebView?
    let invalidatePermissionPageForReplacement: (String) -> Void
    let cleanupCloneWebView: (WKWebView) -> Void
    let commitUntrackedReplacement: (
        WKWebView,
        WKWebView,
        String
    ) -> WebViewDetachedReplacementCommitOutcome
}

@MainActor
final class TabWebViewReplacementContextOwner {
    func makeContext(for tab: Tab) -> TabWebViewReplacementContext {
        TabWebViewReplacementContext(
            existingWebView: {
                tab.resolvedCurrentWebView()
            },
            hasTrackedWebViews: {
                tab.resolvedPrimaryWindowId() != nil
            },
            rebuildTrackedWebViews: { targetURL, reason, configuration in
                tab.navigationRuntime.webViewReplacementRuntime.rebuildTrackedWebViews(
                    tab,
                    tab.resolvedPrimaryWindowId(),
                    targetURL,
                    reason,
                    configuration
                )
            },
            makeNormalTabWebView: { reason in
                tab.makeNormalTabWebView(reason: reason)
            },
            invalidatePermissionPageForReplacement: { reason in
                tab.invalidatePermissionPageForReplacement(reason: reason)
            },
            cleanupCloneWebView: { webView in
                tab.cleanupCloneWebView(webView)
            },
            commitUntrackedReplacement: { previous, replacement, reason in
                tab.navigationRuntime.webViewReplacementRuntime.commitUntrackedReplacement(
                    tab,
                    previous,
                    replacement,
                    reason
                )
            }
        )
    }
}

@MainActor
final class TabWebViewReplacementOwner {
    @discardableResult
    func replaceNormalWebView(
        targetURL: URL,
        reason: String,
        context: TabWebViewReplacementContext,
        onReplacementFailure: () -> Void = { /* No-op. */ }
    ) -> TabWebViewReplacementOutcome {
        replaceCurrentWebView(
            targetURL: targetURL,
            reason: reason,
            configuration: .normal,
            context: context,
            makeReplacementWebView: context.makeNormalTabWebView,
            onReplacementFailure: onReplacementFailure
        )
    }

    @discardableResult
    func replaceCurrentWebView(
        targetURL: URL,
        reason: String,
        configuration: DeferredWebViewRebuildConfiguration,
        context: TabWebViewReplacementContext,
        makeReplacementWebView: (String) -> WKWebView?,
        onReplacementFailure: () -> Void = { /* No-op. */ }
    ) -> TabWebViewReplacementOutcome {
        guard let previousWebView = context.existingWebView() else { return .notNeeded }

        if context.hasTrackedWebViews() {
            switch context.rebuildTrackedWebViews(targetURL, reason, configuration) {
            case .committed:
                return .replacedAndScheduledNavigation
            case .deferred:
                return .deferred
            case .noLiveWindows, .failed:
                onReplacementFailure()
                return .failed
            }
        }

        guard let replacementWebView = makeReplacementWebView(reason) else {
            onReplacementFailure()
            return .failed
        }

        switch context.commitUntrackedReplacement(
            previousWebView,
            replacementWebView,
            reason
        ) {
        case .committed:
            context.invalidatePermissionPageForReplacement(reason)
            return .replacedNavigationPending
        case .rejected:
            context.cleanupCloneWebView(replacementWebView)
            onReplacementFailure()
            return .failed
        case .consumedByFailedTransaction:
            onReplacementFailure()
            return .failed
        }
    }
}
