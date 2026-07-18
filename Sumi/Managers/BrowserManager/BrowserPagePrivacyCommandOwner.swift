import WebKit

@MainActor
final class BrowserPagePrivacyCommandOwner {
    private let activePages: ActivePageResolver
    private let dataServices: BrowserManagerDataServices
    private let profiles: BrowserCurrentProfileAuthority
    private let webViews: BrowserWebViewRoutingService

    init(
        activePages: ActivePageResolver,
        dataServices: BrowserManagerDataServices,
        profiles: BrowserCurrentProfileAuthority,
        webViews: BrowserWebViewRoutingService
    ) {
        self.activePages = activePages
        self.dataServices = dataServices
        self.profiles = profiles
        self.webViews = webViews
    }

    func clearCurrentPageCookies() {
        clearCookies(for: activePages.resolveActiveWindow())
    }

    func clearCookies(for page: ActivePageResolution?) {
        guard let page, !page.tab.representsSumiNativeSurface else { return }
        dataServices.privacyService.clearCurrentPageCookies(
            using: context(for: page)
        )
    }

    func hardReloadCurrentPage() {
        hardReload(activePages.resolveActiveWindow())
    }

    func hardReload(_ page: ActivePageResolution?) {
        guard let page, !page.tab.representsSumiNativeSurface else { return }
        dataServices.privacyService.hardReloadCurrentPage(
            using: context(for: page)
        )
    }

    private func context(
        for page: ActivePageResolution
    ) -> BrowserPrivacyService.Context {
        BrowserPrivacyService.Context(
            currentDataStore: { [profiles] in
                page.tab.resolveProfile()?.dataStore
                    ?? profiles.currentProfile?.dataStore
                    ?? WKWebsiteDataStore.default()
            },
            currentTab: {
                page.tab
            },
            activeWindowId: {
                page.windowState.id
            },
            reloadWindowScopedPage: { [webViews] tab, windowID, reason, policy in
                guard windowID == page.windowState.id else { return }
                if page.source == .glancePreview,
                   page.tab.id == tab.id {
                    _ = tab.navigationCommandOwner.refresh(tab)
                    return
                }
                _ = webViews.refreshPage(
                    for: tab,
                    in: page.windowState,
                    reason: reason,
                    policy: policy
                )
            }
        )
    }
}
