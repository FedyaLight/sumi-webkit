import SwiftData

@MainActor
extension BrowserManager {
    func clearCurrentPageCookies() {
        privacyService.clearCurrentPageCookies(using: makePrivacyContext())
    }

    func clearAllCookies() {
        privacyService.clearAllCookies(using: makePrivacyContext())
    }

    func clearExpiredCookies() {
        privacyService.clearExpiredCookies(using: makePrivacyContext())
    }

    func clearCurrentPageCache() {
        privacyService.clearCurrentPageCache(using: makePrivacyContext())
    }

    func hardReloadCurrentPage() {
        privacyService.hardReloadCurrentPage(using: makePrivacyContext())
    }

    func clearStaleCache() {
        privacyService.clearStaleCache(using: makePrivacyContext())
    }

    func clearDiskCache() {
        privacyService.clearDiskCache(using: makePrivacyContext())
    }

    func clearMemoryCache() {
        privacyService.clearMemoryCache(using: makePrivacyContext())
    }

    func clearAllCache() {
        privacyService.clearAllCache(using: makePrivacyContext())
    }

    func clearThirdPartyCookies() {
        privacyService.clearThirdPartyCookies(using: makePrivacyContext())
    }

    func clearHighRiskCookies() {
        privacyService.clearHighRiskCookies(using: makePrivacyContext())
    }

    func performPrivacyCleanup() {
        privacyService.performPrivacyCleanup(using: makePrivacyContext())
    }

    func clearCurrentProfileCookies() {
        privacyService.clearCurrentProfileCookies(using: makePrivacyContext())
    }

    func clearCurrentProfileCache() {
        privacyService.clearCurrentProfileCache(using: makePrivacyContext())
    }

    func clearAllProfilesCookies() {
        privacyService.clearAllProfilesCookies(using: makePrivacyContext())
    }

    func performPrivacyCleanupAllProfiles() {
        privacyService.performPrivacyCleanupAllProfiles(using: makePrivacyContext())
    }

    func clearPersonalDataCache() {
        privacyService.clearPersonalDataCache(using: makePrivacyContext())
    }

    func clearFaviconCache() {
        privacyService.clearFaviconCache(using: makePrivacyContext())
    }

    private func makePrivacyContext() -> BrowserPrivacyService.Context {
        BrowserPrivacyService.Context(
            cookieManager: cookieManager,
            cacheManager: cacheManager,
            currentTab: { [weak self] in
                self?.currentTabForActiveWindow()
            },
            activeWindowId: { [weak self] in
                self?.windowRegistry?.activeWindow?.id
            },
            currentProfileId: { [weak self] in
                self?.currentProfile?.id
            },
            profiles: { [weak self] in
                self?.profileManager.profiles ?? []
            },
            webViewLookup: { [weak self] tabId, windowId in
                self?.getWebView(for: tabId, in: windowId)
            }
        )
    }
}
