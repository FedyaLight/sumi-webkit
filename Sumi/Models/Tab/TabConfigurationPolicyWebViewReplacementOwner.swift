import Foundation
import WebKit

@MainActor
struct TabConfigurationPolicyWebViewReplacementContext {
    let tabId: UUID
    let existingWebView: () -> WKWebView?
    let primaryWindowId: UUID?
    let trackedWindowIdContainingWebView: (WKWebView) -> UUID?
    let hasTrackedWebViews: (UUID) -> Bool
    let setTrackedWebView: (WKWebView, UUID, UUID) -> Void
    let makeNormalTabWebView: (String) -> WKWebView?
    let invalidateCurrentPermissionPageForWebViewReplacement: (String) -> Void
    let removeTrackedWebViews: () -> Bool
    let cleanupCloneWebView: (WKWebView) -> Void
    let clearCurrentWebViewOwnership: () -> Void
    let replaceUntrackedWebView: (WKWebView) -> Void
    let assignWebViewToWindow: (WKWebView, UUID) -> Void
    let refreshWindowAfterWebViewReplacement: (UUID) -> Void
}

@MainActor
final class TabConfigurationPolicyWebViewReplacementOwner {
    @discardableResult
    func replaceNormalWebView(
        reason: String,
        context: TabConfigurationPolicyWebViewReplacementContext,
        onTrackedWebViewRemovalFailure: () -> Void = {}
    ) -> Bool {
        guard let previousWebView = context.existingWebView() else { return false }

        let previousWindowId = context.primaryWindowId
            ?? context.trackedWindowIdContainingWebView(previousWebView)
        let hadTrackedWebViews = context.hasTrackedWebViews(context.tabId)

        guard let replacementWebView = context.makeNormalTabWebView(reason) else {
            return false
        }
        context.invalidateCurrentPermissionPageForWebViewReplacement(reason)

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
