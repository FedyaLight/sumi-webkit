import WebKit

@MainActor
final class BrowserPagePrivacyCommandOwner {
    private let activePages: ActivePageResolver
    private let windows: WindowRegistry
    private let dataServices: BrowserManagerDataServices
    private let profiles: BrowserCurrentProfileAuthority
    private let webViews: BrowserWebViewRoutingService

    init(
        activePages: ActivePageResolver,
        windows: WindowRegistry,
        dataServices: BrowserManagerDataServices,
        profiles: BrowserCurrentProfileAuthority,
        webViews: BrowserWebViewRoutingService
    ) {
        self.activePages = activePages
        self.windows = windows
        self.dataServices = dataServices
        self.profiles = profiles
        self.webViews = webViews
    }

    func clearCurrentPageCookies() {
        guard let tab = activePages.resolveActiveWindow()?.tab,
              !tab.representsSumiNativeSurface else {
            return
        }
        dataServices.privacyService.clearCurrentPageCookies(using: context)
    }

    func hardReloadCurrentPage() {
        guard let tab = activePages.resolveActiveWindow()?.tab,
              !tab.representsSumiNativeSurface else {
            return
        }
        dataServices.privacyService.hardReloadCurrentPage(using: context)
    }

    private var context: BrowserPrivacyService.Context {
        BrowserPrivacyService.Context(
            currentDataStore: { [activePages, profiles] in
                activePages.resolveActiveWindow()?.tab.resolveProfile()?.dataStore
                    ?? profiles.currentProfile?.dataStore
                    ?? WKWebsiteDataStore.default()
            },
            currentTab: { [activePages] in
                activePages.resolveActiveWindow()?.tab
            },
            activeWindowId: { [windows] in
                windows.activeWindow?.id
            },
            reloadWindowScopedPage: { [activePages, webViews, windows] tab, windowID, reason, policy in
                guard let windowState = windows.windows[windowID] else { return }
                if let page = activePages.resolve(in: windowState),
                   page.source == .glancePreview,
                   page.tab.id == tab.id {
                    _ = page.tab.navigationCommandOwner.refresh(page.tab)
                    return
                }
                _ = webViews.refreshPage(
                    for: tab,
                    in: windowState,
                    reason: reason,
                    policy: policy
                )
            }
        )
    }
}
