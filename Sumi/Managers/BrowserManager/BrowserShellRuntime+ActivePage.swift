import Foundation

extension BrowserShellRuntime {
    func makeActivePageResolver() -> ActivePageResolver {
        ActivePageResolver(
            activeWindow: { [weak self] in
                self?.windowRegistry.activeWindow
            },
            selectedTab: { [weak self] windowState in
                self?.windowTabs.currentTab(for: windowState)
            },
            glanceSnapshot: { [weak self] windowState in
                guard let self,
                      let glanceManager,
                      let session = glanceManager.activeSession(for: windowState)
                else { return nil }
                return ActivePageResolver.GlanceSnapshot(
                    tab: session.previewTab,
                    url: session.currentURL,
                    webView: glanceManager.activePreviewWebView(for: windowState)
                )
            },
            windowOwnedWebView: { [weak self] tab, windowID in
                self?.webViewSessions.webView(for: tab.id, in: windowID)
            }
        )
    }
}
