import Foundation

@MainActor
protocol BrowserFaviconServicing: AnyObject {
    func partition(profile: Profile?) -> SumiFaviconPartition
    func invalidateSite(domain: String, profile: Profile?)

#if DEBUG
    func drainRuntimeTasksForTests(cancel: Bool) async
#endif
}

extension SumiFaviconSystem: BrowserFaviconServicing {}

@MainActor
protocol BrowserSiteDataPolicyEnforcing: AnyObject {
    func enforceBlockStorageIfNeeded(for url: URL?, profile: Profile?)
    func performAllWindowsClosedCleanup(profiles: [Profile]) async
}

extension SumiSiteDataPolicyEnforcementService: BrowserSiteDataPolicyEnforcing {}

@MainActor
protocol BrowserAutomaticBrowsingDataCleanupScheduling: AnyObject {
    func scheduleIfNeeded(
        retentionPeriod: SumiBrowsingDataRetentionPeriod,
        historyManager: HistoryManager,
        profiles: [Profile],
        currentProfileId: UUID?,
        force: Bool,
        reason: String,
        delayNanoseconds: UInt64?
    )
}

extension SumiAutomaticBrowsingDataCleanupService: BrowserAutomaticBrowsingDataCleanupScheduling {}

@MainActor
protocol BrowserPrivacyServicing: AnyObject {
    func clearCurrentPageCookies(using context: BrowserPrivacyService.Context)
    func hardReloadCurrentPage(using context: BrowserPrivacyService.Context)
}

extension BrowserPrivacyService: BrowserPrivacyServicing {}

@MainActor
struct BrowserManagerDataServices {
    let browsingDataCleanupService: SumiBrowsingDataCleanupService
    let automaticBrowsingDataCleanupService: any BrowserAutomaticBrowsingDataCleanupScheduling
    let siteDataPolicyEnforcementService: any BrowserSiteDataPolicyEnforcing
    let faviconService: any BrowserFaviconServicing
    let privacyService: any BrowserPrivacyServicing

    static var production: Self {
        let websiteDataCleanupService = SumiWebsiteDataCleanupService.shared
        let faviconSystem = SumiFaviconSystem.shared
        return BrowserManagerDataServices(
            browsingDataCleanupService: .shared,
            automaticBrowsingDataCleanupService: SumiAutomaticBrowsingDataCleanupService(
                websiteDataCleanupService: websiteDataCleanupService,
                faviconCacheCleaner: faviconSystem
            ),
            siteDataPolicyEnforcementService: SumiSiteDataPolicyEnforcementService(
                cleanupService: websiteDataCleanupService
            ),
            faviconService: faviconSystem,
            privacyService: BrowserPrivacyService(
                cleanupService: websiteDataCleanupService,
                faviconInvalidator: { domain, profile in
                    faviconSystem.invalidateSite(domain: domain, profile: profile)
                }
            )
        )
    }

    func replacing(
        browsingDataCleanupService: SumiBrowsingDataCleanupService
    ) -> BrowserManagerDataServices {
        BrowserManagerDataServices(
            browsingDataCleanupService: browsingDataCleanupService,
            automaticBrowsingDataCleanupService: automaticBrowsingDataCleanupService,
            siteDataPolicyEnforcementService: siteDataPolicyEnforcementService,
            faviconService: faviconService,
            privacyService: privacyService
        )
    }
}
