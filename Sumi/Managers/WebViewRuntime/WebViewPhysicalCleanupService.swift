import Foundation
import SumiWebRuntime
import WebKit

/// Final physical shutdown boundary for an already-ownerless WebView.
/// Canonical residence changes must happen before entering this service.
@MainActor
final class WebViewPhysicalCleanupService {
    private let webViewSessions: WebViewSessionRepository
    private let processRecovery: WebContentProcessRecoveryService
    private let mediaProtection: WebViewMediaProtectionOwner
    private let protectedCommands: DeferredProtectedCommandScheduler
    private let runtimeAssembler: WebViewRuntimeAssembler

    init(
        webViewSessions: WebViewSessionRepository,
        processRecovery: WebContentProcessRecoveryService,
        mediaProtection: WebViewMediaProtectionOwner,
        protectedCommands: DeferredProtectedCommandScheduler,
        runtimeAssembler: WebViewRuntimeAssembler
    ) {
        self.webViewSessions = webViewSessions
        self.processRecovery = processRecovery
        self.mediaProtection = mediaProtection
        self.protectedCommands = protectedCommands
        self.runtimeAssembler = runtimeAssembler
    }

    func clean(_ webView: WKWebView, tabID: UUID) {
        processRecovery.cancel(webView)
        switch webViewSessions.residence(of: webView) {
        case .pendingCleanup(let lease) where lease.tabID == tabID:
            return
        case nil:
            break
        default:
            assertionFailure("Fallback cleanup requires an ownerless WebView")
            return
        }

        if mediaProtection.isProtected(webView) {
            guard let lease = webViewSessions.beginPendingCleanup(
                of: webView,
                for: tabID
            ) else {
                preconditionFailure(
                    "Protected fallback cleanup could not acquire ownership"
                )
            }
            switch protectedCommands.schedule(
                .performFallbackWebViewCleanup(
                    webViewID: ObjectIdentifier(webView),
                    lease: lease
                ),
                for: webView,
                reason: "WebViewPhysicalCleanupService.clean"
            ) {
            case .scheduled:
                return
            case .notProtected:
                precondition(
                    webViewSessions.consumePendingCleanup(
                        of: webView,
                        lease: lease
                    ),
                    "Fallback cleanup lost its ownership lease"
                )
            case .invalidTarget, .droppedAtCapacity:
                preconditionFailure(
                    "Guaranteed fallback cleanup could not be scheduled"
                )
            }
        }

        RuntimeDiagnostics.debug(category: "WebViewPhysicalCleanup") {
            "Shutting down ownerless WebView for tab=\(tabID.uuidString.prefix(8))."
        }
        SumiWebViewShutdown.perform(
            on: webView,
            tabId: tabID,
            runtime: runtimeAssembler.shutdownRuntime()
        )
    }
}
