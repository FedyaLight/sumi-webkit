import WebKit

@MainActor
extension BrowserManager {
    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        if glanceManager.handleWebViewDidClose(webView) {
            return true
        }

        return webViewCoordinator?.handleWebViewDidClose(webView) ?? false
    }
}
