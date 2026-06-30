@MainActor
extension BrowserManager {
    func sidebarHeaderBrowserContext(
        for windowState: BrowserWindowState
    ) -> SidebarHeaderBrowserContext {
        urlBarContextOwner.sidebarHeaderContext(for: windowState)
    }

    var urlBarBrowserContext: URLBarBrowserContext {
        urlBarContextOwner.urlBarContext
    }

    var urlBarHubBrowserContext: URLBarHubBrowserContext {
        urlBarContextOwner.urlBarHubContext
    }

    func navigationToolbarContext(
        for windowState: BrowserWindowState
    ) -> NavigationToolbarBrowserContext {
        urlBarContextOwner.navigationToolbarContext(for: windowState)
    }

    func navigationHistoryContext(
        for windowState: BrowserWindowState
    ) -> SumiNavigationHistoryContext {
        urlBarContextOwner.navigationHistoryContext(for: windowState)
    }
}
