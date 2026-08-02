import Foundation
import SumiWebRuntime
import WebKit

/// Compositor-mutation protection and deferred-command scheduling for exact
/// WebView identities. It owns no window presentation or canonical placement.
@MainActor
final class WebViewProtectionRuntime {
    private let mediaProtection: WebViewMediaProtectionOwner
    private let commandAdmission: DeferredProtectedCommandAdmissionService
    private let commandProcessor: DeferredProtectedCommandProcessor
    private let processRecovery: WebContentProcessRecoveryService
    private let webViewSessions: WebViewSessionRepository
    private let webViews: WebViewRuntimeWebViewResolver
    private let visibleRuntime: VisibleWebViewRuntimeOwner
    private let websiteDataCleanup: WebsiteDataCleanupService

    init(
        mediaProtection: WebViewMediaProtectionOwner,
        commandAdmission: DeferredProtectedCommandAdmissionService,
        commandProcessor: DeferredProtectedCommandProcessor,
        processRecovery: WebContentProcessRecoveryService,
        webViewSessions: WebViewSessionRepository,
        webViews: WebViewRuntimeWebViewResolver,
        visibleRuntime: VisibleWebViewRuntimeOwner,
        websiteDataCleanup: WebsiteDataCleanupService
    ) {
        self.mediaProtection = mediaProtection
        self.commandAdmission = commandAdmission
        self.commandProcessor = commandProcessor
        self.processRecovery = processRecovery
        self.webViewSessions = webViewSessions
        self.webViews = webViews
        self.visibleRuntime = visibleRuntime
        self.websiteDataCleanup = websiteDataCleanup
    }

    func beginHistorySwipe(
        tabID: UUID,
        webView: WKWebView,
        originURL: URL?,
        originHistoryItem: WKBackForwardListItem?
    ) {
        let windowID = webViewSessions.trackedOwner(containing: webView)?.windowID
        let webViewID = mediaProtection.beginHistorySwipeProtection(
            on: webView,
            windowID: windowID,
            originURL: originURL,
            originHistoryItem: originHistoryItem
        )
        RuntimeDiagnostics.swipeTrace(
            "begin tab=\(tabID.uuidString.prefix(8)) window=\(windowID?.uuidString.prefix(8) ?? "nil") webView=\(webViewID) url=\((originURL ?? originHistoryItem?.url)?.absoluteString ?? "nil")"
        )
    }

    @discardableResult
    func finishHistorySwipe(
        tabID: UUID,
        webView: WKWebView?,
        currentURL: URL?,
        currentHistoryItem: WKBackForwardListItem?
    ) -> Bool {
        guard let result = mediaProtection.finishHistorySwipeProtection(
            on: webView,
            currentURL: currentURL,
            currentHistoryItem: currentHistoryItem
        ) else {
            return false
        }
        RuntimeDiagnostics.swipeTrace(
            "finish tab=\(tabID.uuidString.prefix(8)) webView=\(result.webViewID) cancelled=\(result.wasCancelled) url=\((currentURL ?? currentHistoryItem?.url)?.absoluteString ?? "nil")"
        )
        flush(for: result.webViewID)
        return result.wasCancelled
    }

    func hasActiveHistorySwipe(in windowID: UUID) -> Bool {
        mediaProtection.hasActiveHistorySwipe(in: windowID)
    }

    func isProtected(_ webView: WKWebView) -> Bool {
        mediaProtection.isProtected(webView)
    }

    func beginVisualHandoff(
        for webView: WKWebView,
        containerRegistration: WebViewCompositorContainerRegistration
    ) -> WebViewVisualHandoffProtectionLease? {
        guard visibleRuntime.isCurrentCompositorContainerRegistration(
            containerRegistration
        ) else {
            return nil
        }
        return mediaProtection.beginVisualHandoffProtection(for: webView)
    }

    func finishVisualHandoff(_ lease: WebViewVisualHandoffProtectionLease) {
        guard let webViewID = mediaProtection.finishVisualHandoffProtection(lease) else {
            return
        }
        flush(for: webViewID)
    }

    @discardableResult
    func deferCleanup(
        of webView: WKWebView,
        tabID: UUID,
        reason: String
    ) -> Bool {
        schedule(
            .cleanupTabWebView(
                webViewID: ObjectIdentifier(webView),
                tabID: tabID
            ),
            for: webView,
            reason: reason
        ).wasScheduled
    }

    func schedule(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String
    ) -> DeferredProtectedCommandSchedulingOutcome {
        commandAdmission.schedule(command, for: webView, reason: reason)
    }

    func resolveWebView(with identifier: ObjectIdentifier) -> WKWebView? {
        webViews.resolve(identifier)
    }

    func flush(for webViewID: ObjectIdentifier) {
        commandProcessor.flushCommands(for: webViewID)
        processRecovery.retryPendingImmediately(for: webViewID)
    }

    func pruneInvalidCommands(reason: String) {
        let staleIDs = mediaProtection.pruneStaleBookkeeping(
            reason: "\(reason).staleBookkeeping"
        )
        websiteDataCleanup.webViewsDidLeaveRuntime(staleIDs)
        commandAdmission.pruneInvalidCommands(reason: reason)
    }
}
