import WebKit

/// Routes page-privacy commands (clear current-page cookies, hard reload)
/// through `BrowserPrivacyService` with window-scoped page context.
@MainActor
final class BrowserPagePrivacyCommandOwner {
    struct Dependencies {
        let privacyService: @MainActor () -> (any BrowserPrivacyServicing)?
        let activePageTab: @MainActor () -> Tab?
        let makePrivacyContext: @MainActor () -> BrowserPrivacyService.Context?
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func clearCurrentPageCookies() {
        guard let tab = dependencies.activePageTab(), !tab.representsSumiNativeSurface,
              let context = dependencies.makePrivacyContext()
        else { return }
        dependencies.privacyService()?.clearCurrentPageCookies(using: context)
    }

    func hardReloadCurrentPage() {
        guard let tab = dependencies.activePageTab(), !tab.representsSumiNativeSurface,
              let context = dependencies.makePrivacyContext()
        else { return }
        dependencies.privacyService()?.hardReloadCurrentPage(using: context)
    }
}

extension BrowserPagePrivacyCommandOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            privacyService: { [weak browserManager] in
                browserManager?.dataServices.privacyService
            },
            activePageTab: { [weak browserManager] in
                browserManager?.activePageRoutingOwner.activePageTabForActiveWindow()
            },
            makePrivacyContext: { [weak browserManager] in
                guard browserManager != nil else { return nil }
                return BrowserPrivacyService.Context(
                    currentDataStore: { [weak browserManager] in
                        browserManager?.activePageRoutingOwner.activePageTabForActiveWindow()?.resolveProfile()?.dataStore
                            ?? browserManager?.currentProfile?.dataStore
                            ?? WKWebsiteDataStore.default()
                    },
                    currentTab: { [weak browserManager] in
                        browserManager?.activePageRoutingOwner.activePageTabForActiveWindow()
                    },
                    activeWindowId: { [weak browserManager] in
                        browserManager?.windowRegistry?.activeWindow?.id
                    },
                    webViewLookup: { [weak browserManager] tab, windowId in
                        browserManager?.windowOwnedWebView(for: tab, in: windowId)
                    },
                    reloadWindowScopedPage: { [weak browserManager] tab, windowId, reason in
                        guard let browserManager,
                              let windowState = browserManager.windowRegistry?.windows[windowId]
                        else { return }
                        browserManager.windowScopedNavigationOwner.refreshWindowScopedPage(
                            tab: tab,
                            in: windowState,
                            reason: reason
                        )
                    }
                )
            }
        )
    }
}
