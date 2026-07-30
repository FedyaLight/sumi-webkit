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
    func clearFaviconPartition(for profile: Profile) throws

#if DEBUG
    func drainRuntimeTasksForTests(cancel: Bool) async
#endif
}

extension SumiFaviconSystem: BrowserFaviconServicing {}

protocol BrowserFaviconImageReading: AnyObject, Sendable {
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
}

@MainActor
protocol BrowserEssentialBackdropReading: AnyObject, Sendable {
    func cachedBackdrop(
        for documentURL: URL,
        partition: SumiFaviconPartition
    ) -> NSImage?
    func loadBackdrop(
        for documentURL: URL,
        partition: SumiFaviconPartition
    ) async -> NSImage?
}

private final class UnavailableEssentialBackdropReader:
    BrowserEssentialBackdropReading,
    @unchecked Sendable {
    nonisolated static let shared = UnavailableEssentialBackdropReader()

    func cachedBackdrop(
        for _: URL,
        partition _: SumiFaviconPartition
    ) -> NSImage? {
        nil
    }

    func loadBackdrop(
        for _: URL,
        partition _: SumiFaviconPartition
    ) async -> NSImage? {
        nil
    }
}

protocol BrowserFaviconLiveDiscoveryIngesting: AnyObject, Sendable {
    @MainActor
    func ingestVisibleTabDiscovery(
        links: [SumiFaviconDiscoveredLink],
        documentURL: URL,
        baseURL: URL?,
        partition: SumiFaviconPartition,
        webView: WKWebView?,
        aliasPageURLs: [URL]
    ) async -> NSImage?
}

protocol BrowserFaviconLocalIconIngesting: AnyObject, Sendable {
    func ingestLocalExtensionIcon(
        fileURL: URL,
        documentURL: URL,
        partition: SumiFaviconPartition,
        context: SumiFaviconDisplayContext
    ) async -> NSImage?

    /// Stores an icon recovered from another browser's cache, so an imported
    /// sidebar shows real icons immediately rather than filling in as the user
    /// revisits each site.
    func ingestImportedIcon(
        payload: Data,
        iconURL: URL,
        documentURL: URL,
        partition: SumiFaviconPartition
    ) async
}

protocol BrowserFaviconPrefetchScheduling: AnyObject, Sendable {
    func scheduleColdFetch(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        priority: SumiFaviconFetchPriority
    )
}

struct BrowserFaviconCapabilities: Sendable {
    let images: any BrowserFaviconImageReading
    let liveDiscovery: any BrowserFaviconLiveDiscoveryIngesting
    let localIconIngestion: any BrowserFaviconLocalIconIngesting
    let prefetch: any BrowserFaviconPrefetchScheduling
    let essentialBackdrops: any BrowserEssentialBackdropReading

    init(
        images: any BrowserFaviconImageReading,
        liveDiscovery: any BrowserFaviconLiveDiscoveryIngesting,
        localIconIngestion: any BrowserFaviconLocalIconIngesting,
        prefetch: any BrowserFaviconPrefetchScheduling,
        essentialBackdrops: (any BrowserEssentialBackdropReading)? = nil
    ) {
        self.images = images
        self.liveDiscovery = liveDiscovery
        self.localIconIngestion = localIconIngestion
        self.prefetch = prefetch
        self.essentialBackdrops = essentialBackdrops
            ?? UnavailableEssentialBackdropReader.shared
    }
}

extension SumiFaviconImageRepository: BrowserFaviconImageReading {}

extension SumiFaviconLiveDiscoveryPipeline: BrowserFaviconLiveDiscoveryIngesting {
    func ingestVisibleTabDiscovery(
        links: [SumiFaviconDiscoveredLink],
        documentURL: URL,
        baseURL: URL?,
        partition: SumiFaviconPartition,
        webView: WKWebView?,
        aliasPageURLs: [URL]
    ) async -> NSImage? {
        await ingest(
            links: links,
            documentURL: documentURL,
            baseURL: baseURL,
            partition: partition,
            webView: webView,
            aliasPageURLs: aliasPageURLs
        )
    }
}

extension SumiFaviconPayloadIngestion: BrowserFaviconLocalIconIngesting {
    func ingestImportedIcon(
        payload: Data,
        iconURL: URL,
        documentURL: URL,
        partition: SumiFaviconPartition
    ) async {
        // A rejected icon (unsupported format, oversized) is not worth failing
        // an import over; the site refetches it on first visit.
        try? storeExternalPayload(
            payload,
            faviconURL: iconURL,
            documentURL: documentURL,
            partition: partition
        )
    }
}

extension SumiFaviconColdFetchService: BrowserFaviconPrefetchScheduling {
    func scheduleColdFetch(
        for pageURL: URL,
        partition: SumiFaviconPartition,
        priority: SumiFaviconFetchPriority
    ) {
        schedule(pageURL: pageURL, partition: partition, priority: priority)
    }
}

@MainActor
protocol BrowserSiteDataPolicyEnforcing: AnyObject {
    func attachDestructiveCleanupPreparer(
        _ preparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    )
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
    func deletePolicies(profileId: UUID) throws
}

extension SumiSiteDataPolicyStore: BrowserSiteDataPolicyStoring {}

@MainActor
protocol PrivatePartitionResidueCleaning: AnyObject {
    func cleanup(profileID: UUID)
}

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
    func attachDestructiveCleanupPreparer(
        _ preparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    )
    func scheduleIfNeeded(_ request: SumiBrowsingDataCleanupScheduleRequest)
}

extension SumiAutomaticBrowsingDataCleanupService: BrowsingDataCleanupScheduling {}

@MainActor
protocol BrowserPrivacyServicing: AnyObject {
    func attachDestructiveCleanupPreparer(
        _ preparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    )
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
    let profileWebsiteDataMutationService: any SumiProfileWebsiteDataMutating
    let browsingDataCleanupService: SumiBrowsingDataCleanupService
    let automaticBrowsingDataCleanupService: any BrowsingDataCleanupScheduling
    let siteDataPolicyStore: any BrowserSiteDataPolicyStoring
    let siteDataPolicyEnforcementService: any BrowserSiteDataPolicyEnforcing
    let faviconService: any BrowserFaviconServicing
    let faviconCapabilities: BrowserFaviconCapabilities
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
        faviconCapabilities: BrowserFaviconCapabilities,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging,
        historyFaviconCleaner: any HistoryFaviconCleaning,
        historyVisitedLinkStore: any HistoryVisitedLinkStoring,
        privacyService: any BrowserPrivacyServicing,
        profileWebsiteDataMutationService: (any SumiProfileWebsiteDataMutating)? = nil
    ) {
        self.websiteDataCleanupService = websiteDataCleanupService
        self.profileWebsiteDataMutationService = profileWebsiteDataMutationService
            ?? SumiProfileWebsiteDataMutationService(
                cleanupService: websiteDataCleanupService
            )
        self.browsingDataCleanupService = browsingDataCleanupService
        self.automaticBrowsingDataCleanupService = automaticBrowsingDataCleanupService
        self.siteDataPolicyStore = siteDataPolicyStore
        self.siteDataPolicyEnforcementService = siteDataPolicyEnforcementService
        self.faviconService = faviconService
        self.faviconCapabilities = faviconCapabilities
        self.visitedLinkStore = visitedLinkStore
        self.historyFaviconCleaner = historyFaviconCleaner
        self.historyVisitedLinkStore = historyVisitedLinkStore
        self.privacyService = privacyService
    }

    static var productionVisitedLinkStore: any BrowserVisitedLinkStoreManaging {
        SharedVisitedLinkStoreComposition.provider
    }

    static func production(
        database: SumiDatabase,
        faviconSystem: SumiFaviconSystem
    ) -> Self {
        make(
            database: database,
            faviconService: faviconSystem,
            faviconCapabilities: faviconSystem.capabilities,
            historyFaviconCleaner: faviconSystem,
            browsingDataFaviconCleaner: faviconSystem
        )
    }

    static func unavailable() -> Self {
        make(
            database: nil,
            faviconService: TabDependencyIsolationDefaults.faviconService,
            faviconCapabilities: TabDependencyIsolationDefaults.faviconCapabilities,
            historyFaviconCleaner: TabDependencyIsolationDefaults.historyFaviconCleaner,
            browsingDataFaviconCleaner: TabDependencyIsolationDefaults.browsingDataFaviconCleaner
        )
    }

    private static func make(
        database: SumiDatabase?,
        faviconService: any BrowserFaviconServicing,
        faviconCapabilities: BrowserFaviconCapabilities,
        historyFaviconCleaner: any HistoryFaviconCleaning,
        browsingDataFaviconCleaner: any SumiBrowsingDataFaviconCleaning
    ) -> Self {
        let websiteDataCleanupService = SumiWebsiteDataCleanupService()
        let siteDataPolicyStore = SumiSiteDataPolicyStore(database: database)
        let visitedLinkStore = SharedVisitedLinkStoreComposition.provider
        let basicAuthCredentialStore = BasicAuthCredentialStore()
        return BrowserManagerDataServices(
            websiteDataCleanupService: websiteDataCleanupService,
            browsingDataCleanupService: SumiBrowsingDataCleanupService(
                websiteDataCleanupService: websiteDataCleanupService,
                faviconCacheCleaner: browsingDataFaviconCleaner,
                appResidueCleaner: SumiBrowsingDataAppResidueCleaner(),
                basicAuthCredentialStore: basicAuthCredentialStore,
                visitedLinkStore: visitedLinkStore
            ),
            automaticBrowsingDataCleanupService: SumiAutomaticBrowsingDataCleanupService(
                websiteDataCleanupService: websiteDataCleanupService,
                faviconCacheCleaner: browsingDataFaviconCleaner,
                basicAuthCredentialStore: basicAuthCredentialStore
            ),
            siteDataPolicyStore: siteDataPolicyStore,
            siteDataPolicyEnforcementService: SumiSiteDataPolicyEnforcementService(
                policyStore: siteDataPolicyStore,
                cleanupService: websiteDataCleanupService
            ),
            faviconService: faviconService,
            faviconCapabilities: faviconCapabilities,
            visitedLinkStore: visitedLinkStore,
            historyFaviconCleaner: historyFaviconCleaner,
            historyVisitedLinkStore: visitedLinkStore,
            privacyService: BrowserPrivacyService(
                cleanupService: websiteDataCleanupService,
                faviconInvalidator: { domain, profile in
                    faviconService.invalidateSite(domain: domain, profile: profile)
                }
            )
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
        let resolvedProfileWebsiteDataMutationService =
            (profileWebsiteDataMutationService as? SumiProfileWebsiteDataMutationService)?
            .replacingCleanupService(websiteDataCleanupService)
            ?? profileWebsiteDataMutationService
        return BrowserManagerDataServices(
            websiteDataCleanupService: websiteDataCleanupService,
            browsingDataCleanupService: browsingDataCleanupService,
            automaticBrowsingDataCleanupService: automaticBrowsingDataCleanupService,
            siteDataPolicyStore: siteDataPolicyStore,
            siteDataPolicyEnforcementService: resolvedSiteDataPolicyEnforcementService,
            faviconService: faviconService,
            faviconCapabilities: faviconCapabilities,
            visitedLinkStore: visitedLinkStore,
            historyFaviconCleaner: historyFaviconCleaner,
            historyVisitedLinkStore: historyVisitedLinkStore,
            privacyService: resolvedPrivacyService,
            profileWebsiteDataMutationService: resolvedProfileWebsiteDataMutationService
        )
    }
}
