import WebKit

@MainActor
final class BrowserPrivacyService {
    struct Context {
        let cookieManager: CookieManager
        let cacheManager: CacheManager
        let currentTab: @MainActor () -> Tab?
        let activeWindowId: @MainActor () -> UUID?
        let currentProfileId: @MainActor () -> UUID?
        let profiles: @MainActor () -> [Profile]
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

        Task { @MainActor in
            await context.cacheManager.clearCacheForDomainExcludingCookies(host)
            if let webView = context.webViewLookup(currentTab.id, activeWindowId) {
                let targetURL = webView.url ?? currentTab.url
                if #available(macOS 15.5, *) {
                    currentTab.performMainFrameNavigationAfterHydrationIfNeeded(
                        on: webView,
                        url: targetURL
                    ) { resolvedWebView in
                        resolvedWebView.reloadFromOrigin()
                    }
                } else {
                    currentTab.performMainFrameNavigation(
                        on: webView,
                        url: targetURL
                    ) { resolvedWebView in
                        resolvedWebView.reloadFromOrigin()
                    }
                }
            } else {
                if let webView = currentTab.existingWebView {
                    let targetURL = webView.url ?? currentTab.url
                    if #available(macOS 15.5, *) {
                        currentTab.performMainFrameNavigationAfterHydrationIfNeeded(
                            on: webView,
                            url: targetURL
                        ) { resolvedWebView in
                            resolvedWebView.reloadFromOrigin()
                        }
                    } else {
                        currentTab.performMainFrameNavigation(
                            on: webView,
                            url: targetURL
                        ) { resolvedWebView in
                            resolvedWebView.reloadFromOrigin()
                        }
                    }
                }
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

    func clearCurrentProfileCookies(using context: Context) {
        guard let profileId = context.currentProfileId() else { return }
        RuntimeDiagnostics.emit(
            "🧹 [PrivacyService] Clearing cookies for current profile: \(profileId.uuidString)"
        )
        Task {
            await context.cookieManager.deleteAllCookies()
        }
    }

    func clearCurrentProfileCache(using context: Context) {
        guard context.currentProfileId() != nil else { return }
        RuntimeDiagnostics.emit("🧹 [PrivacyService] Clearing cache for current profile")
        Task {
            await context.cacheManager.clearAllCache()
        }
    }

    func clearAllProfilesCookies(using context: Context) {
        let profiles = context.profiles()
        RuntimeDiagnostics.emit(
            "🧹 [PrivacyService] Clearing cookies for ALL profiles (sequential, isolated)"
        )
        Task { @MainActor in
            for profile in profiles {
                let cookieManager = CookieManager(dataStore: profile.dataStore)
                RuntimeDiagnostics.emit(
                    "   → Clearing cookies for profile=\(profile.id.uuidString) [\(profile.name)]"
                )
                await cookieManager.deleteAllCookies()
            }
        }
    }

    func performPrivacyCleanupAllProfiles(using context: Context) {
        let profiles = context.profiles()
        RuntimeDiagnostics.emit(
            "🧹 [PrivacyService] Performing privacy cleanup across ALL profiles (sequential, isolated)"
        )
        Task { @MainActor in
            for profile in profiles {
                RuntimeDiagnostics.emit(
                    "   → Cleaning profile=\(profile.id.uuidString) [\(profile.name)]"
                )
                let cookieManager = CookieManager(dataStore: profile.dataStore)
                let cacheManager = CacheManager(dataStore: profile.dataStore)
                await cookieManager.performPrivacyCleanup()
                await cacheManager.performPrivacyCompliantCleanup()
            }
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
