import AppKit
import Combine
import Foundation
import WebKit

@MainActor
protocol BrowserFaviconServicing: AnyObject {
    func partition(profile: Profile?) -> SumiFaviconPartition
    func invalidateSite(domain: String, profile: Profile?)
    func syncShortcutPins(_ pins: [ShortcutPin])
    func syncBookmarks(
        _ bookmarks: [SumiBookmark],
        partition: SumiFaviconPartition
    )
    func clearFaviconPartition(for profile: Profile)

#if DEBUG
    func drainRuntimeTasksForTests(cancel: Bool) async
#endif
}

extension SumiFaviconSystem: BrowserFaviconServicing {}

protocol BrowserFaviconImageServicing: AnyObject, Sendable {
    func cachedPreparedImage(for request: SumiPreparedFaviconRequest) -> NSImage?
    func cachedSelection(
        for pageURL: URL,
        partition: SumiFaviconPartition
    ) -> SumiStoredFaviconSelection?
    func preparedImage(
        for request: SumiPreparedFaviconRequest,
        priority: SumiFaviconFetchPriority,
        scheduleFetchOnMiss: Bool
    ) async -> NSImage?
    @MainActor
    func ingestVisibleTabDiscovery(
        links: [SumiFaviconDiscoveredLink],
        documentURL: URL,
        baseURL: URL?,
        partition: SumiFaviconPartition,
        webView: WKWebView?,
        aliasPageURLs: [URL]
    ) async -> NSImage?
    func scheduleColdFetch(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        priority: SumiFaviconFetchPriority
    )
    func ingestLocalExtensionIcon(
        fileURL: URL,
        documentURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext
    ) async -> NSImage?
}

extension SumiFaviconService: BrowserFaviconImageServicing {}

@MainActor
protocol BrowserSiteDataPolicyEnforcing: AnyObject {
    func setBlockStorage(
        _ isEnabled: Bool,
        forHost host: String,
        profile: Profile?
    ) async
    func setDeleteWhenAllWindowsClosed(
        _ isEnabled: Bool,
        forHost host: String,
        profile: Profile?
    )
    func enforceBlockStorageIfNeeded(for url: URL?, profile: Profile?)
    func performAllWindowsClosedCleanup(profiles: [Profile]) async
}

extension SumiSiteDataPolicyEnforcementService: BrowserSiteDataPolicyEnforcing {}

@MainActor
protocol BrowserSiteDataPolicyStoring: AnyObject {
    var changesPublisher: AnyPublisher<Void, Never> { get }
    func state(forHost host: String, profileId: UUID?) -> SumiSiteDataPolicyState
    func hostsWithPolicies(profileId: UUID?) -> Set<String>
}

extension SumiSiteDataPolicyStore: BrowserSiteDataPolicyStoring {}

@MainActor
struct SumiBrowsingDataCleanupScheduleRequest {
    var retentionPeriod: SumiBrowsingDataRetentionPeriod
    var historyManager: HistoryManager
    var profiles: [Profile]
    var currentProfileId: UUID?
    var force: Bool = false
    var reason: String
    var delayNanoseconds: UInt64?
}

@MainActor
protocol BrowsingDataCleanupScheduling: AnyObject {
    func scheduleIfNeeded(_ request: SumiBrowsingDataCleanupScheduleRequest)
}

extension SumiAutomaticBrowsingDataCleanupService: BrowsingDataCleanupScheduling {}

@MainActor
protocol BrowserPrivacyServicing: AnyObject {
    func clearCurrentPageCookies(using context: BrowserPrivacyService.Context)
    func hardReloadCurrentPage(using context: BrowserPrivacyService.Context)
}

extension BrowserPrivacyService: BrowserPrivacyServicing {}

@MainActor
protocol BrowserVisitedLinkStoreManaging: SumiVisitedLinkStoreReplacing {
    func applyStore(to configuration: WKWebViewConfiguration, for profile: Profile)
    func applyStore(to configuration: WKWebViewConfiguration, profileId: UUID)
    func applyStoreFromSourceIfAvailable(
        to configuration: WKWebViewConfiguration,
        source: WKWebViewConfiguration?
    )
    func enableVisitedLinkRecording(on webView: WKWebView)
    func recordVisitedLink(
        _ url: URL,
        for profile: Profile,
        sourceConfiguration: WKWebViewConfiguration?
    )
    func preloadVisitedLinks(_ urls: [URL], for profileId: UUID)
    func discardStore(for profileId: UUID)
}

extension SharedVisitedLinkStoreProvider: BrowserVisitedLinkStoreManaging {}

@MainActor
struct BrowserManagerDataServices {
    let websiteDataCleanupService: any SumiWebsiteDataCleanupServicing
    let browsingDataCleanupService: SumiBrowsingDataCleanupService
    let automaticBrowsingDataCleanupService: any BrowsingDataCleanupScheduling
    let siteDataPolicyStore: any BrowserSiteDataPolicyStoring
    let siteDataPolicyEnforcementService: any BrowserSiteDataPolicyEnforcing
    let faviconService: any BrowserFaviconServicing
    let faviconImageService: any BrowserFaviconImageServicing
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging
    let historyFaviconCleaner: any HistoryFaviconCleaning
    let historyVisitedLinkStore: any HistoryVisitedLinkStoring
    let privacyService: any BrowserPrivacyServicing

    init(
        websiteDataCleanupService: any SumiWebsiteDataCleanupServicing,
        browsingDataCleanupService: SumiBrowsingDataCleanupService,
        automaticBrowsingDataCleanupService: any BrowsingDataCleanupScheduling,
        siteDataPolicyStore: any BrowserSiteDataPolicyStoring,
        siteDataPolicyEnforcementService: any BrowserSiteDataPolicyEnforcing,
        faviconService: any BrowserFaviconServicing,
        faviconImageService: any BrowserFaviconImageServicing = Self.productionFaviconImageService,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging,
        historyFaviconCleaner: any HistoryFaviconCleaning,
        historyVisitedLinkStore: any HistoryVisitedLinkStoring,
        privacyService: any BrowserPrivacyServicing
    ) {
        self.websiteDataCleanupService = websiteDataCleanupService
        self.browsingDataCleanupService = browsingDataCleanupService
        self.automaticBrowsingDataCleanupService = automaticBrowsingDataCleanupService
        self.siteDataPolicyStore = siteDataPolicyStore
        self.siteDataPolicyEnforcementService = siteDataPolicyEnforcementService
        self.faviconService = faviconService
        self.faviconImageService = faviconImageService
        self.visitedLinkStore = visitedLinkStore
        self.historyFaviconCleaner = historyFaviconCleaner
        self.historyVisitedLinkStore = historyVisitedLinkStore
        self.privacyService = privacyService
    }

    private static var productionFaviconSystem: SumiFaviconSystem {
        SumiFaviconSystem.shared
    }

    static var productionFaviconService: any BrowserFaviconServicing {
        productionFaviconSystem
    }

    static var productionFaviconImageService: any BrowserFaviconImageServicing {
        productionFaviconSystem.service
    }

    static var productionVisitedLinkStore: any BrowserVisitedLinkStoreManaging {
        SharedVisitedLinkStoreProvider.shared
    }

    static var production: Self {
        let websiteDataCleanupService = SumiWebsiteDataCleanupService.shared
        let siteDataPolicyStore = SumiSiteDataPolicyStore.shared
        let faviconSystem = productionFaviconSystem
        let visitedLinkStore = SharedVisitedLinkStoreProvider.shared
        let basicAuthCredentialStore = BasicAuthCredentialStore()
        return BrowserManagerDataServices(
            websiteDataCleanupService: websiteDataCleanupService,
            browsingDataCleanupService: SumiBrowsingDataCleanupService(
                websiteDataCleanupService: websiteDataCleanupService,
                faviconCacheCleaner: faviconSystem,
                appResidueCleaner: SumiBrowsingDataAppResidueCleaner(),
                basicAuthCredentialStore: basicAuthCredentialStore,
                visitedLinkStore: visitedLinkStore
            ),
            automaticBrowsingDataCleanupService: SumiAutomaticBrowsingDataCleanupService(
                websiteDataCleanupService: websiteDataCleanupService,
                faviconCacheCleaner: faviconSystem,
                basicAuthCredentialStore: basicAuthCredentialStore
            ),
            siteDataPolicyStore: siteDataPolicyStore,
            siteDataPolicyEnforcementService: SumiSiteDataPolicyEnforcementService(
                policyStore: siteDataPolicyStore,
                cleanupService: websiteDataCleanupService
            ),
            faviconService: faviconSystem,
            faviconImageService: faviconSystem.service,
            visitedLinkStore: visitedLinkStore,
            historyFaviconCleaner: faviconSystem,
            historyVisitedLinkStore: visitedLinkStore,
            privacyService: BrowserPrivacyService(
                cleanupService: websiteDataCleanupService,
                faviconInvalidator: { domain, profile in
                    faviconSystem.invalidateSite(domain: domain, profile: profile)
                }
            )
        )
    }

    var historyManagerDependencies: HistoryManager.Dependencies {
        HistoryManager.Dependencies(
            faviconCleaner: historyFaviconCleaner,
            visitedLinkStore: historyVisitedLinkStore
        )
    }

    func replacing(
        browsingDataCleanupService: SumiBrowsingDataCleanupService
    ) -> BrowserManagerDataServices {
        let websiteDataCleanupService = browsingDataCleanupService.websiteDataCleanupService
        let resolvedSiteDataPolicyEnforcementService =
            (siteDataPolicyEnforcementService as? SumiSiteDataPolicyEnforcementService)?
            .replacingCleanupService(websiteDataCleanupService)
            ?? siteDataPolicyEnforcementService
        let resolvedPrivacyService =
            (privacyService as? BrowserPrivacyService)?
            .replacingCleanupService(websiteDataCleanupService)
            ?? privacyService
        return BrowserManagerDataServices(
            websiteDataCleanupService: websiteDataCleanupService,
            browsingDataCleanupService: browsingDataCleanupService,
            automaticBrowsingDataCleanupService: automaticBrowsingDataCleanupService,
            siteDataPolicyStore: siteDataPolicyStore,
            siteDataPolicyEnforcementService: resolvedSiteDataPolicyEnforcementService,
            faviconService: faviconService,
            faviconImageService: faviconImageService,
            visitedLinkStore: visitedLinkStore,
            historyFaviconCleaner: historyFaviconCleaner,
            historyVisitedLinkStore: historyVisitedLinkStore,
            privacyService: resolvedPrivacyService
        )
    }
}
