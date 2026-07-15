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

@MainActor
extension BrowserAuxiliaryWindowComposition {
    /// Test-only bridge from a WebKit callback witness to the registry-issued
    /// receipt. Production destructive APIs remain receipt-only.
    func teardownAuxiliaryWindowForTesting(
        _ webView: WKWebView,
        reason: AuxiliaryWindowCloseReason
    ) {
        guard let session = sessions.session(for: webView),
              let receipt = sessions.receipt(for: session) else { return }
        teardown.teardown(receipt, reason: reason)
    }
}
