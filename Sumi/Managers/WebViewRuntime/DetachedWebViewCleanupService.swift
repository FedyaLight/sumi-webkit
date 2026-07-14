import SumiWebRuntime
import WebKit

/// Releases detached canonical residence into an exact cleanup lease and owns
/// its immediate or protection-deferred physical destruction.
@MainActor
final class DetachedWebViewCleanupService {
    private let runtimeTabs: WebViewRuntimeTabRegistry
    private let webViewSessions: WebViewSessionRepository
    private let websiteDataCleanup: WebsiteDataCleanupService
    private let processRecovery: WebContentProcessRecoveryService
    private let mediaProtection: WebViewMediaProtectionOwner
    private let protectedCommands: DeferredProtectedCommandAdmissionService

    init(
        runtimeTabs: WebViewRuntimeTabRegistry,
        webViewSessions: WebViewSessionRepository,
        websiteDataCleanup: WebsiteDataCleanupService,
        processRecovery: WebContentProcessRecoveryService,
        mediaProtection: WebViewMediaProtectionOwner,
        protectedCommands: DeferredProtectedCommandAdmissionService
    ) {
        self.runtimeTabs = runtimeTabs
        self.webViewSessions = webViewSessions
        self.websiteDataCleanup = websiteDataCleanup
        self.processRecovery = processRecovery
        self.mediaProtection = mediaProtection
        self.protectedCommands = protectedCommands
    }

    func releaseUntracked(for tab: Tab) {
        guard runtimeTabs.bind(tab).isAccepted else { return }
        guard let webView = tab.webViewSession.untrackedWebView else { return }
        guard let lease = webViewSessions.releaseUntrackedAndBeginPendingCleanup(
            webView,
            for: tab.id
        ) else {
            preconditionFailure(
                "Untracked WebView release lost its expected repository residence"
            )
        }
        finish(webView, lease: lease, tab: tab, reason: "releaseUntracked")
    }

    func releaseParked(
        _ webView: WKWebView,
        for tab: Tab,
        reason: String
    ) -> Bool {
        guard runtimeTabs.bind(tab).isAccepted else { return false }
        guard let lease = webViewSessions.releaseParkedAndBeginPendingCleanup(
            webView,
            for: tab.id
        ) else {
            return false
        }
        finish(webView, lease: lease, tab: tab, reason: reason)
        return true
    }

    private func finish(
        _ webView: WKWebView,
        lease: WebViewPendingCleanupLease,
        tab: Tab,
        reason: String
    ) {
        websiteDataCleanup.webViewDidLeaveRuntime(webView)
        processRecovery.cancel(webView)
        if mediaProtection.isProtected(webView) {
            switch protectedCommands.schedule(
                .performFallbackWebViewCleanup(
                    webViewID: ObjectIdentifier(webView),
                    lease: lease
                ),
                for: webView,
                reason: reason
            ) {
            case .scheduled:
                return
            case .notProtected:
                break
            case .invalidTarget, .droppedAtCapacity:
                preconditionFailure(
                    "Guaranteed leased WebView cleanup could not be scheduled"
                )
            }
        }

        precondition(
            webViewSessions.consumePendingCleanup(of: webView, lease: lease),
            "Leased WebView cleanup lost its exact repository claim"
        )
        tab.cleanupCloneWebView(webView)
    }
}
