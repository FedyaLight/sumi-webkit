import WebKit

@MainActor
final class BrowserPrivacyService {
    struct Context {
        let currentDataStore: @MainActor () -> WKWebsiteDataStore
        let currentTab: @MainActor () -> Tab?
        let activeWindowId: @MainActor () -> UUID?
        let webViewLookup: @MainActor (UUID, UUID) -> WKWebView?
    }

    private let cleanupService: any SumiWebsiteDataCleanupServicing

    init(cleanupService: (any SumiWebsiteDataCleanupServicing)? = nil) {
        self.cleanupService = cleanupService ?? SumiWebsiteDataCleanupService.shared
    }

    func clearCurrentPageCookies(using context: Context) {
        guard let host = context.currentTab()?.url.host else { return }
        let dataStore = context.currentDataStore()
        Task {
            await cleanupService.removeCookies(.domains([host]), in: dataStore)
        }
    }

    func hardReloadCurrentPage(using context: Context) {
        guard let currentTab = context.currentTab(),
              let host = currentTab.url.host,
              let activeWindowId = context.activeWindowId()
        else { return }

        if let webView = context.webViewLookup(currentTab.id, activeWindowId) {
            reloadFromOrigin(currentTab, webView: webView)
        } else if let webView = currentTab.existingWebView {
            reloadFromOrigin(currentTab, webView: webView)
        }

        Task { @MainActor in
            let dataStore = context.currentDataStore()
            await cleanupService.removeWebsiteDataForDomain(
                host,
                includingCookies: false,
                in: dataStore
            )
            SumiFaviconSystem.shared.invalidateSite(
                domain: host,
                profile: currentTab.resolveProfile()
            )
        }
    }

    private func reloadFromOrigin(_ tab: Tab, webView: WKWebView) {
        let targetURL = webView.url ?? tab.url
        if tab.protectionAttachmentRequiresNormalWebViewRebuild(for: targetURL)
            || tab.autoplayPolicyRequiresNormalWebViewRebuild(for: targetURL) {
            tab.refresh()
            return
        }
        tab.performMainFrameNavigationAfterHydrationIfNeeded(
            on: webView
        ) { resolvedWebView in
            resolvedWebView.reloadFromOrigin()
        }
    }
}
