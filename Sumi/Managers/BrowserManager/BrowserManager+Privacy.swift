import WebKit

@MainActor
extension BrowserManager {
    func clearCurrentPageCookies() {
        guard let tab = activePageTabForActiveWindow(), !tab.representsSumiNativeSurface else { return }
        dataServices.privacyService.clearCurrentPageCookies(using: makePrivacyContext())
    }

    func hardReloadCurrentPage() {
        guard let tab = activePageTabForActiveWindow(), !tab.representsSumiNativeSurface else { return }
        dataServices.privacyService.hardReloadCurrentPage(using: makePrivacyContext())
    }

    private func makePrivacyContext() -> BrowserPrivacyService.Context {
        BrowserPrivacyService.Context(
            currentDataStore: { [weak self] in
                self?.activePageTabForActiveWindow()?.resolveProfile()?.dataStore
                    ?? self?.currentProfile?.dataStore
                    ?? WKWebsiteDataStore.default()
            },
            currentTab: { [weak self] in
                self?.activePageTabForActiveWindow()
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
