import WebKit
import SumiWebRuntime

@MainActor
final class BrowserPrivacyService {
    struct Context {
        let currentDataStore: @MainActor () -> WKWebsiteDataStore
        let currentTab: @MainActor () -> Tab?
        let activeWindowId: @MainActor () -> UUID?
        let reloadWindowScopedPage: @MainActor (
            Tab,
            UUID,
            String,
            WebRuntimeMainFrameReloadPolicy
        ) -> Void
    }

    private let cleanupService: any SumiWebsiteDataCleanupServicing
    private let invalidateFaviconSite: @MainActor (String, Profile?) -> Void
    var destructiveCleanupPreparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?

    init(
        cleanupService: any SumiWebsiteDataCleanupServicing,
        faviconInvalidator: @escaping @MainActor (String, Profile?) -> Void
    ) {
        self.cleanupService = cleanupService
        self.invalidateFaviconSite = faviconInvalidator
    }

    func replacingCleanupService(
        _ cleanupService: any SumiWebsiteDataCleanupServicing
    ) -> BrowserPrivacyService {
        let replacement = BrowserPrivacyService(
            cleanupService: cleanupService,
            faviconInvalidator: invalidateFaviconSite
        )
        replacement.destructiveCleanupPreparer = destructiveCleanupPreparer
        return replacement
    }

    func attachDestructiveCleanupPreparer(
        _ preparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    ) {
        destructiveCleanupPreparer = preparer
    }

    func clearCurrentPageCookies(using context: Context) {
        guard let tab = context.currentTab(),
              let host = tab.url.host,
              let profileID = tab.resolveProfile()?.id ?? tab.profileId,
              let destructiveCleanupPreparer else { return }
        let dataStore = context.currentDataStore()
        Task { @MainActor in
            _ = await destructiveCleanupPreparer.performDestructiveDataCleanup(
                profileIDs: [profileID]
            ) {
                await self.cleanupService.removeCookies(
                    .domains([host]),
                    in: dataStore
                )
            }
        }
    }

    func hardReloadCurrentPage(using context: Context) {
        guard let currentTab = context.currentTab(),
              let host = currentTab.url.host,
              let activeWindowId = context.activeWindowId()
        else { return }

        let profile = currentTab.resolveProfile()
        invalidateFaviconSite(host, profile)
        context.reloadWindowScopedPage(
            currentTab,
            activeWindowId,
            "BrowserPrivacyService.hardReload",
            .fromOrigin
        )
    }

}
