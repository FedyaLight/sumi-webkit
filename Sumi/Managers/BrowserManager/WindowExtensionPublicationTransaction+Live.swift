import Foundation

@MainActor
extension WindowExtensionPublicationTransaction {
    static func live(
        browserManager: BrowserManager,
        webViewOwnership: WebViewOwnershipQuery
    ) -> WindowExtensionPublicationTransaction {
        return WindowExtensionPublicationTransaction(
            preparation: browserManager.optionalModules.extensions,
            publication: browserManager.optionalModules.extensions,
            resolveInitialTab: {
                [weak browserManager, weak webViewOwnership] window in
                guard let browserManager,
                      let tab = browserManager.shellRuntime.windowTabs
                      .currentTab(for: window),
                      let webView = webViewOwnership?.webView(
                          for: tab.id,
                          in: window.id
                      ) as? FocusableWKWebView
                else {
                    return nil
                }
                return (tab, webView)
            }
        )
    }
}
