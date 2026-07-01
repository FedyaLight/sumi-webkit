import Foundation
import WebKit

@MainActor
struct TabWebViewReplacementContext {
    let tabId: UUID
    let existingWebView: () -> WKWebView?
    let primaryWindowId: UUID?
    let trackedWindowIdContainingWebView: (WKWebView) -> UUID?
    let hasTrackedWebViews: (UUID) -> Bool
    let setTrackedWebView: (WKWebView, UUID, UUID) -> Void
    let makeNormalTabWebView: (String) -> WKWebView?
    let invalidatePermissionPageForReplacement: (String) -> Void
    let removeTrackedWebViews: () -> Bool
    let cleanupCloneWebView: (WKWebView) -> Void
    let clearCurrentWebViewOwnership: () -> Void
    let replaceUntrackedWebView: (WKWebView) -> Void
    let assignWebViewToWindow: (WKWebView, UUID) -> Void
    let refreshWindowAfterWebViewReplacement: (UUID) -> Void
}

@MainActor
final class TabWebViewReplacementContextOwner {
    func makeContext(for tab: Tab) -> TabWebViewReplacementContext {
        TabWebViewReplacementContext(
            tabId: tab.id,
            existingWebView: {
                tab.existingWebView
            },
            primaryWindowId: tab.primaryWindowId,
            trackedWindowIdContainingWebView: { webView in
                tab.webViewReplacementRuntime
                    .trackedWindowIdContainingWebView(webView)
            },
            hasTrackedWebViews: { tabId in
                tab.webViewReplacementRuntime.hasTrackedWebViews(tabId)
            },
            setTrackedWebView: { webView, tabId, windowId in
                tab.webViewReplacementRuntime.setTrackedWebView(
                    webView,
                    tabId,
                    windowId
                )
            },
            makeNormalTabWebView: { reason in
                tab.makeNormalTabWebView(reason: reason)
            },
            invalidatePermissionPageForReplacement: { reason in
                tab.invalidatePermissionPageForReplacement(reason: reason)
            },
            removeTrackedWebViews: {
                tab.webViewReplacementRuntime.removeTrackedWebViews(tab)
            },
            cleanupCloneWebView: { webView in
                tab.cleanupCloneWebView(webView)
            },
            clearCurrentWebViewOwnership: {
                tab.clearCurrentWebViewOwnership()
            },
            replaceUntrackedWebView: { webView in
                tab.replaceUntrackedWebView(webView)
            },
            assignWebViewToWindow: { webView, windowId in
                tab.assignWebViewToWindow(webView, windowId: windowId)
            },
            refreshWindowAfterWebViewReplacement: { windowId in
                tab.webViewReplacementRuntime
                    .refreshWindowAfterWebViewReplacement(windowId)
            }
        )
    }
}

@MainActor
final class TabWebViewReplacementOwner {
    @discardableResult
    func replaceNormalWebView(
        reason: String,
        context: TabWebViewReplacementContext,
        onTrackedWebViewRemovalFailure: () -> Void = { /* No-op. */ }
    ) -> Bool {
        guard let previousWebView = context.existingWebView() else { return false }

        let previousWindowId = context.primaryWindowId
            ?? context.trackedWindowIdContainingWebView(previousWebView)
        let hadTrackedWebViews = context.hasTrackedWebViews(context.tabId)

        guard let replacementWebView = context.makeNormalTabWebView(reason) else {
            return false
        }
        context.invalidatePermissionPageForReplacement(reason)

        let removedTrackedWebViews = context.removeTrackedWebViews()
        if hadTrackedWebViews && !removedTrackedWebViews {
            onTrackedWebViewRemovalFailure()
            return false
        }

        if !removedTrackedWebViews {
            context.cleanupCloneWebView(previousWebView)
            context.clearCurrentWebViewOwnership()
        }

        if let previousWindowId {
            context.setTrackedWebView(replacementWebView, context.tabId, previousWindowId)
            context.assignWebViewToWindow(replacementWebView, previousWindowId)
            context.refreshWindowAfterWebViewReplacement(previousWindowId)
        } else {
            context.replaceUntrackedWebView(replacementWebView)
        }

        return true
    }
}
