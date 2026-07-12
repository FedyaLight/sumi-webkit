import SumiWebRuntime
import WebKit

/// Resolves exact WebView identities from canonical sessions first, then from
/// the weak protection ledger used while a detached view is still protected.
@MainActor
final class WebViewRuntimeWebViewResolver {
    private let sessions: WebViewSessionRepository
    private let mediaProtection: WebViewMediaProtectionOwner

    init(
        sessions: WebViewSessionRepository,
        mediaProtection: WebViewMediaProtectionOwner
    ) {
        self.sessions = sessions
        self.mediaProtection = mediaProtection
    }

    func resolve(_ identifier: ObjectIdentifier) -> WKWebView? {
        if let webView = sessions.webView(with: identifier) {
            mediaProtection.note(webView)
            return webView
        }
        return mediaProtection.resolveWeakWebView(with: identifier)
    }
}
