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

        return requireWebViewCoordinator().handleWebViewDidClose(webView)
    }

    func closeAuxiliaryMiniWindow(
        for tab: Tab,
        reason: AuxiliaryWindowCloseReason = .extensionRequestedClose
    ) {
        guard tabManager.isAuxiliaryMiniWindowTab(tab) else { return }

        if let webView = auxiliaryWindowManager.session(for: tab)?.webView {
            auxiliaryWindowManager.teardown(for: webView, reason: reason)
            return
        }

        tabManager.removeAuxiliaryMiniWindowTab(tab)
        BrowserManagerRuntimeWiring.notifyExtensionTabClosed(tab, for: self)
    }
}
