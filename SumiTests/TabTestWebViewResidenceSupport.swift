import WebKit

@testable import Sumi

@MainActor
extension Tab {
    /// Test-fixture placement for suites whose subject is above the canonical
    /// installation boundary. Production code must use
    /// `UntrackedWebViewInstalling`.
    func replaceUntrackedWebView(_ webView: WKWebView) {
        webViewSession.replaceUntracked(with: webView)
    }

    func adoptParkedWebViewAsCurrent(_ webView: WKWebView) {
        precondition(webViewSession.adoptParkedAsUntracked(webView))
    }
}
