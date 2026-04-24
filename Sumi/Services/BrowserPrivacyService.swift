import WebKit

@MainActor
final class BrowserPrivacyService {
    struct Context {
        let cookieManager: CookieManager
        let cacheManager: CacheManager
        let currentTab: @MainActor () -> Tab?
        let activeWindowId: @MainActor () -> UUID?
        let webViewLookup: @MainActor (UUID, UUID) -> WKWebView?
    }

    func clearCurrentPageCookies(using context: Context) {
        guard let host = context.currentTab()?.url.host else { return }
        Task {
            await context.cookieManager.deleteCookiesForDomain(host)
        }
    }

    func clearAllCookies(using context: Context) {
        Task {
            await context.cookieManager.deleteAllCookies()
        }
    }

    func clearExpiredCookies(using context: Context) {
        Task {
            await context.cookieManager.deleteExpiredCookies()
        }
    }

    func clearCurrentPageCache(using context: Context) {
        guard let host = context.currentTab()?.url.host else { return }
        Task {
            await context.cacheManager.clearCacheForDomain(host)
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

        Task {
            await context.cacheManager.clearCacheForDomainExcludingCookies(host)
        }
    }

    private func reloadFromOrigin(_ tab: Tab, webView: WKWebView) {
        if #available(macOS 15.5, *) {
            tab.performMainFrameNavigationAfterHydrationIfNeeded(
                on: webView
            ) { resolvedWebView in
                resolvedWebView.reloadFromOrigin()
            }
        } else {
            tab.performMainFrameNavigation(
                on: webView
            ) { resolvedWebView in
                resolvedWebView.reloadFromOrigin()
            }
        }
    }

    func clearStaleCache(using context: Context) {
        Task {
            await context.cacheManager.clearStaleCache()
        }
    }

    func clearDiskCache(using context: Context) {
        Task {
            await context.cacheManager.clearDiskCache()
        }
    }

    func clearMemoryCache(using context: Context) {
        Task {
            await context.cacheManager.clearMemoryCache()
        }
    }

    func clearAllCache(using context: Context) {
        Task {
            await context.cacheManager.clearAllCache()
        }
    }

    func clearThirdPartyCookies(using context: Context) {
        Task {
            await context.cookieManager.deleteThirdPartyCookies()
        }
    }

    func clearHighRiskCookies(using context: Context) {
        Task {
            await context.cookieManager.deleteHighRiskCookies()
        }
    }

    func performPrivacyCleanup(using context: Context) {
        Task {
            await context.cookieManager.performPrivacyCleanup()
            await context.cacheManager.performPrivacyCompliantCleanup()
        }
    }

    func clearPersonalDataCache(using context: Context) {
        Task {
            await context.cacheManager.clearPersonalDataCache()
        }
    }

    func clearFaviconCache(using context: Context) {
        context.cacheManager.clearFaviconCache()
    }
}
