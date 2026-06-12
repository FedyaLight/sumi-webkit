import WebKit

@MainActor
extension BrowserManager {
    @discardableResult
    func handleWebViewDidClose(_ webView: WKWebView) -> Bool {
        if glanceManager.handleWebViewDidClose(webView) {
            return true
        }

        if auxiliaryWindowManager.contains(webView: webView) {
            auxiliaryWindowManager.teardown(for: webView, reason: .webViewDidClose)
            return true
        }

        return webViewCoordinator?.handleWebViewDidClose(webView) ?? false
    }

    func closeAuxiliaryMiniWindow(
        for tab: Tab,
        reason: AuxiliaryWindowCloseReason = .extensionRequestedClose
    ) {
        guard tabManager.isAuxiliaryMiniWindowTab(tab) else { return }

        if let webView = tab.existingWebView,
           auxiliaryWindowManager.contains(webView: webView)
        {
            auxiliaryWindowManager.teardown(for: webView, reason: reason)
            return
        }

        tabManager.removeAuxiliaryMiniWindowTab(tab)
        extensionsModule.notifyTabClosedIfLoaded(tab)
    }
}
