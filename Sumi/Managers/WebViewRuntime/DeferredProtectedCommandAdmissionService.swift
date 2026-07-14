import Foundation
import SumiWebRuntime
import WebKit

/// Admits protected commands into the media-protection queue after exact
/// identity and lifetime validation. It owns no execution task or retry timer.
@MainActor
final class DeferredProtectedCommandAdmissionService {
    private let mediaProtection: WebViewMediaProtectionOwner
    private let webViews: WebViewRuntimeWebViewResolver
    private let authority: DeferredWebViewCommandAuthority
    private let retryLedger: DeferredProtectedCommandRetryLedger
    private let finishCleanupSuppression: @MainActor ([ObjectIdentifier]) -> Void

    init(
        mediaProtection: WebViewMediaProtectionOwner,
        webViews: WebViewRuntimeWebViewResolver,
        authority: DeferredWebViewCommandAuthority,
        retryLedger: DeferredProtectedCommandRetryLedger,
        finishCleanupSuppression: @escaping @MainActor ([ObjectIdentifier]) -> Void
    ) {
        self.mediaProtection = mediaProtection
        self.webViews = webViews
        self.authority = authority
        self.retryLedger = retryLedger
        self.finishCleanupSuppression = finishCleanupSuppression
    }

    func schedule(
        _ command: DeferredWebViewCommand,
        for webView: WKWebView,
        reason: String
    ) -> DeferredProtectedCommandSchedulingOutcome {
        mediaProtection.note(webView)
        guard mediaProtection.isProtected(webView) else { return .notProtected }

        let outcome = mediaProtection.enqueueDeferredCommandIfNeeded(
            command,
            for: webView,
            reason: reason,
            resolveWebView: webViews.resolve,
            isCommandValid: isValid,
            dropCommand: drop,
            didPruneStaleWebViewIDs: finishCleanupSuppression
        )
        if outcome.wasScheduled {
            retryLedger.clear(for: ObjectIdentifier(webView))
        }
        return outcome
    }

    func pruneInvalidCommands(reason: String) {
        guard mediaProtection.hasDeferredProtectedCommands else { return }
        finishCleanupSuppression(mediaProtection.pruneInvalidDeferredCommands(
            reason: reason,
            resolveWebView: webViews.resolve,
            isCommandValid: isValid,
            dropCommand: drop
        ))
    }

    private func isValid(_ command: DeferredWebViewCommand) -> Bool {
        authority.prepare(command) != nil
    }

    private func drop(
        _ command: DeferredWebViewCommand,
        sourceWebViewID: ObjectIdentifier,
        reason: String
    ) {
        PerformanceTrace.emitEvent(
            "DeferredProtectedCommandAdmissionService.dropDeferredProtectedCommand"
        )
        RuntimeDiagnostics.protectedWebViewTrace(
            "dropDeferredCommand reason=\(reason) sourceWebView=\(sourceWebViewID) command={\(command.debugSummary)}"
        )
    }
}
