import WebKit

@MainActor
extension BrowserManager {
    func clearCurrentPageCookies() {
        privacyService.clearCurrentPageCookies(using: makePrivacyContext())
    }

    func hardReloadCurrentPage() {
        privacyService.hardReloadCurrentPage(using: makePrivacyContext())
    }

    private func makePrivacyContext() -> BrowserPrivacyService.Context {
        BrowserPrivacyService.Context(
            currentDataStore: { [weak self] in
                self?.currentProfile?.dataStore ?? WKWebsiteDataStore.default()
            },
            currentTab: { [weak self] in
                self?.currentTabForActiveWindow()
            },
            activeWindowId: { [weak self] in
                self?.windowRegistry?.activeWindow?.id
            },
            webViewLookup: { [weak self] tabId, windowId in
                self?.getWebView(for: tabId, in: windowId)
            }
        )
    }
}
