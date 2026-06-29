import Foundation
import Combine
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserManagerRuntimeWiringTests: XCTestCase {
    func testBrowserManagerInitializationAttachesCoreRuntimeManagers() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )

        XCTAssertIdentical(browserManager.compositorManager.browserManager, browserManager)
        XCTAssertIdentical(browserManager.tabManager.browserManager, browserManager)
        XCTAssertTrue(browserManager.tabManager.runtimeContext is BrowserManagerTabRuntimeContext)
        XCTAssertIdentical(browserManager.splitManager.browserManager, browserManager)
        XCTAssertIdentical(browserManager.downloadManager.browserManager, browserManager)
        XCTAssertIdentical(browserManager.extensionsModule.browserManager, browserManager)
        XCTAssertIdentical(browserManager.userscriptsModule.browserManager, browserManager)
        XCTAssertIdentical(browserManager.boostsModule.browserManager, browserManager)
        XCTAssertIdentical(browserManager.auxiliaryWindowManager.browserManager, browserManager)
        XCTAssertIdentical(browserManager.glanceManager.browserManager, browserManager)
        XCTAssertFalse(browserManager.extensionsModule.hasLoadedRuntime)
        XCTAssertFalse(browserManager.userscriptsModule.hasLoadedRuntime)
    }

    func testBrowserManagerInitializationRetainsInjectedPermissionRuntimeDependencies() throws {
        let container = try makeInMemoryStartupContainer()
        let permissionStore = SwiftDataPermissionStore(container: container)
        let recentActivityStore = SumiPermissionRecentActivityStore()
        let siteActivityStore = try makeSiteActivityStore()
        let indicatorEventStore = SumiPermissionIndicatorEventStore()
        let cleanupService = SumiPermissionCleanupService(
            store: permissionStore,
            recentActivityStore: recentActivityStore,
            antiAbuseStore: SumiPermissionAntiAbuseStore(userDefaults: nil)
        )
        let blockedPopupStore = SumiBlockedPopupStore()
        let externalSchemeSessionStore = SumiExternalSchemeSessionStore()

        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(container: container),
            permissionIndicatorEventStore: indicatorEventStore,
            permissionRecentActivityStore: recentActivityStore,
            permissionSiteActivityStore: siteActivityStore,
            permissionCleanupService: cleanupService,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalSchemeSessionStore
        )

        XCTAssertIdentical(browserManager.permissionIndicatorEventStore, indicatorEventStore)
        XCTAssertIdentical(browserManager.permissionRecentActivityStore, recentActivityStore)
        XCTAssertIdentical(browserManager.permissionSiteActivityStore, siteActivityStore)
        XCTAssertIdentical(browserManager.permissionCleanupService, cleanupService)
        XCTAssertIdentical(browserManager.blockedPopupStore, blockedPopupStore)
        XCTAssertIdentical(browserManager.externalSchemeSessionStore, externalSchemeSessionStore)
        XCTAssertIdentical(browserManager.permissionBridges.permissionIndicatorEventStore, indicatorEventStore)
        XCTAssertIdentical(browserManager.permissionBridges.blockedPopupStore, blockedPopupStore)
        XCTAssertIdentical(browserManager.permissionBridges.externalSchemeSessionStore, externalSchemeSessionStore)
    }

    func testBrowserManagerPermissionFacadesRouteThroughScopedBridgeRegistry() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let registry = browserManager.permissionBridges

        XCTAssertIdentical(browserManager.permissionRuntime.permissionBridges, registry)
        XCTAssertIdentical(browserManager.webKitPermissionBridge, registry.webKitPermissionBridge)
        XCTAssertIdentical(browserManager.webKitGeolocationBridge, registry.webKitGeolocationBridge)
        XCTAssertIdentical(browserManager.notificationPermissionBridge, registry.notificationPermissionBridge)
        XCTAssertIdentical(browserManager.filePickerPermissionBridge, registry.filePickerPermissionBridge)
        XCTAssertIdentical(browserManager.storageAccessPermissionBridge, registry.storageAccessPermissionBridge)
        XCTAssertIdentical(browserManager.popupPermissionBridge, registry.popupPermissionBridge)
        XCTAssertIdentical(browserManager.externalSchemePermissionBridge, registry.externalSchemePermissionBridge)
        XCTAssertIdentical(browserManager.permissionLifecycleController, registry.permissionLifecycleController)
    }

    func testPermissionBridgeOverridesAreScopedToRegistry() throws {
        let container = try makeInMemoryStartupContainer()
        let systemPermissionService = FakeSumiSystemPermissionService()
        let permissionCoordinator = SumiPermissionCoordinator(
            policyResolver: DefaultSumiPermissionPolicyResolver(
                systemPermissionService: systemPermissionService
            ),
            persistentStore: nil,
            antiAbuseStore: nil,
            sessionOwnerId: "browser-manager-runtime-wiring-tests"
        )
        let blockedPopupStore = SumiBlockedPopupStore()
        let siteActivityStore = try makeSiteActivityStore()
        let popupBridge = SumiPopupPermissionBridge(
            coordinator: permissionCoordinator,
            blockedPopupStore: blockedPopupStore,
            siteActivityStore: siteActivityStore
        )

        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(container: container),
            systemPermissionService: systemPermissionService,
            permissionCoordinator: permissionCoordinator,
            permissionSiteActivityStore: siteActivityStore,
            blockedPopupStore: blockedPopupStore,
            permissionBridgeOverrides: BrowserPermissionBridgeRegistry.Overrides(
                popupPermissionBridge: popupBridge
            )
        )

        XCTAssertIdentical(browserManager.permissionBridges.popupPermissionBridge, popupBridge)
        XCTAssertIdentical(browserManager.popupPermissionBridge, popupBridge)
        XCTAssertIdentical(browserManager.permissionBridges.blockedPopupStore, blockedPopupStore)
    }

    func testWebViewCoordinatorWiringUsesInjectedBrowsingDataCleanupService() throws {
        let cleanupService = makeBrowsingDataCleanupService()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            browsingDataCleanupService: cleanupService,
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let coordinator = WebViewCoordinator()

        browserManager.webViewCoordinator = coordinator

        let preparer = try XCTUnwrap(cleanupService.destructiveCleanupPreparer)
        XCTAssertIdentical(preparer as AnyObject, coordinator)
    }

    func testBrowserManagerRuntimeDataServicesUseInjectedBundle() async throws {
        let browsingDataCleanupService = makeBrowsingDataCleanupService()
        let automaticCleanupService = FakeAutomaticBrowsingDataCleanupScheduler()
        let siteDataPolicyService = FakeBrowserSiteDataPolicyService()
        let faviconService = FakeBrowserFaviconService()
        let visitedLinkStore = FakeBrowserVisitedLinkStore()
        let privacyService = FakeBrowserPrivacyService()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            dataServices: BrowserManagerDataServices(
                websiteDataCleanupService: FakeWebsiteDataCleanupService(),
                browsingDataCleanupService: browsingDataCleanupService,
                automaticBrowsingDataCleanupService: automaticCleanupService,
                siteDataPolicyStore: try makeSiteDataPolicyStore(),
                siteDataPolicyEnforcementService: siteDataPolicyService,
                faviconService: faviconService,
                visitedLinkStore: visitedLinkStore,
                historyFaviconCleaner: faviconService,
                historyVisitedLinkStore: visitedLinkStore,
                privacyService: privacyService
            ),
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let initialProfile = try XCTUnwrap(browserManager.currentProfile)

        XCTAssertIdentical(browserManager.browsingDataCleanupService, browsingDataCleanupService)
        XCTAssertEqual(faviconService.partitionProfileIds, [initialProfile.id])

        let tab = Tab(
            url: URL(string: "https://example.com/path")!,
            browserManager: browserManager,
            loadsCachedFaviconOnInit: false
        )
        browserManager.enforceSiteDataPolicyAfterNavigation(for: tab)

        XCTAssertEqual(siteDataPolicyService.enforcedURLs, [tab.url])
        XCTAssertEqual(siteDataPolicyService.enforcedProfileIds, [initialProfile.id])

        await browserManager.performSiteDataPolicyAllWindowsClosedCleanup()

        XCTAssertEqual(
            siteDataPolicyService.closedCleanupProfileIds,
            browserManager.profileManager.profiles.map(\.id)
        )

        let suiteName = "BrowserManagerRuntimeDataServicesTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            SumiBrowsingDataRetentionPeriod.sevenDays.rawValue,
            forKey: "settings.browsingData.retentionDays"
        )
        let settings = SumiSettingsService(userDefaults: defaults)
        browserManager.sumiSettings = settings

        XCTAssertEqual(automaticCleanupService.schedules.count, 1)
        XCTAssertEqual(automaticCleanupService.schedules[0].retentionPeriod, .sevenDays)
        XCTAssertEqual(automaticCleanupService.schedules[0].currentProfileId, initialProfile.id)
        XCTAssertEqual(automaticCleanupService.schedules[0].reason, "settings-attached")

        browserManager.scheduleAutomaticBrowsingDataCleanup(
            reason: "unit-test",
            force: true,
            delayNanoseconds: 0
        )

        XCTAssertEqual(automaticCleanupService.schedules.count, 2)
        XCTAssertTrue(automaticCleanupService.schedules[1].force)
        XCTAssertEqual(automaticCleanupService.schedules[1].reason, "unit-test")
        XCTAssertEqual(automaticCleanupService.schedules[1].delayNanoseconds, 0)

        await browserManager.historyManager.clearAll()

        XCTAssertEqual(faviconService.historyClearBurnCount, 1)
    }

    func testNativeSurfaceViewModelsUseInjectedFaviconService() throws {
        let injectedPartition = SumiFaviconPartition(
            profileIdentifier: "injected-view-models",
            isPrivate: true
        )
        let browsingDataCleanupService = makeBrowsingDataCleanupService()
        let faviconService = FakeBrowserFaviconService(partitionToReturn: injectedPartition)
        let visitedLinkStore = FakeBrowserVisitedLinkStore()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            dataServices: BrowserManagerDataServices(
                websiteDataCleanupService: FakeWebsiteDataCleanupService(),
                browsingDataCleanupService: browsingDataCleanupService,
                automaticBrowsingDataCleanupService: FakeAutomaticBrowsingDataCleanupScheduler(),
                siteDataPolicyStore: try makeSiteDataPolicyStore(),
                siteDataPolicyEnforcementService: FakeBrowserSiteDataPolicyService(),
                faviconService: faviconService,
                visitedLinkStore: visitedLinkStore,
                historyFaviconCleaner: faviconService,
                historyVisitedLinkStore: visitedLinkStore,
                privacyService: FakeBrowserPrivacyService()
            ),
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let initialProfile = try XCTUnwrap(browserManager.currentProfile)

        let historyViewModel = HistoryPageViewModel(
            browserManager: browserManager,
            windowState: nil,
            faviconService: browserManager.dataServices.faviconService
        )
        let bookmarksViewModel = SumiBookmarksPageViewModel(
            browserManager: browserManager,
            windowState: nil,
            faviconService: browserManager.dataServices.faviconService
        )

        XCTAssertEqual(historyViewModel.faviconPartition, injectedPartition)
        XCTAssertEqual(bookmarksViewModel.faviconPartition, injectedPartition)
        XCTAssertEqual(
            faviconService.partitionProfileIds,
            [initialProfile.id, initialProfile.id, initialProfile.id]
        )
    }

    func testRuntimeNotificationsPreserveLazyExtensionRuntime() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let windowState = BrowserWindowState()
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let runtimeNotifications = BrowserManagerRuntimeWiring.tabSelectionRuntimeNotifications(
            for: browserManager
        )

        BrowserManagerRuntimeWiring.notifyExtensionWindowOpened(windowState, for: browserManager)
        BrowserManagerRuntimeWiring.notifyExtensionWindowFocused(windowState, for: browserManager)
        runtimeNotifications.tabActivated(tab, nil)
        runtimeNotifications.tabSelectionChanged("test-tab-selection")
        BrowserManagerRuntimeWiring.notifyExtensionTabClosed(tab, for: browserManager)

        XCTAssertFalse(browserManager.extensionsModule.hasLoadedRuntime)
    }

    func testSettingsMiniPlayerFeatureUpdatesUseInjectedNowPlayingController() throws {
        let nowPlayingController = FakeNativeNowPlayingController()
        let suiteName = "BrowserManagerRuntimeWiringNowPlayingSettings-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let settings = SumiSettingsService(
            userDefaults: defaults,
            nowPlayingController: nowPlayingController
        )

        XCTAssertEqual(nowPlayingController.featureEnabledValues, [true])

        settings.sidebarMiniPlayerEnabled = false

        XCTAssertEqual(nowPlayingController.featureEnabledValues, [true, false])
    }

    func testTabMediaLifecycleUsesBrowserManagerInjectedNowPlayingController() throws {
        let nowPlayingController = FakeNativeNowPlayingController()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            nowPlayingController: nowPlayingController,
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let tab = Tab(
            url: URL(string: "https://example.com/video")!,
            browserManager: browserManager,
            loadsCachedFaviconOnInit: false
        )

        tab.applyAudioState(.unmuted(isPlayingAudio: true))

        XCTAssertEqual(nowPlayingController.scheduledRefreshDelays, [0])

        tab.unloadWebView()

        XCTAssertEqual(nowPlayingController.unloadedTabIds, [tab.id])
        XCTAssertEqual(nowPlayingController.scheduledRefreshDelays, [0, 0])
    }

    private func makeBrowsingDataCleanupService() -> SumiBrowsingDataCleanupService {
        SumiBrowsingDataCleanupService(
            websiteDataCleanupService: FakeWebsiteDataCleanupService(),
            faviconCacheCleaner: FakeBrowserFaviconService(),
            appResidueCleaner: SumiBrowsingDataAppResidueCleaner(),
            basicAuthCredentialStore: FakeBrowsingDataCredentialStore(),
            visitedLinkStore: FakeBrowserVisitedLinkStore()
        )
    }

    private func makeSiteDataPolicyStore() throws -> SumiSiteDataPolicyStore {
        let suiteName = "BrowserManagerSiteDataPolicyStoreTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        return SumiSiteDataPolicyStore(userDefaults: defaults)
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }

    private func makeSiteActivityStore() throws -> SumiPermissionSiteActivityStore {
        SumiPermissionSiteActivityStore(
            userDefaults: try XCTUnwrap(
                UserDefaults(suiteName: "BrowserManagerRuntimeWiringTests-\(UUID().uuidString)")
            )
        )
    }
}

@MainActor
private final class FakeNativeNowPlayingController: SumiNativeNowPlayingRuntimeControlling {
    private let subject = CurrentValueSubject<SumiBackgroundMediaCardState?, Never>(nil)
    private(set) var featureEnabledValues: [Bool] = []
    private(set) var scheduledRefreshDelays: [UInt64] = []
    private(set) var activatedTabIds: [UUID] = []
    private(set) var unloadedTabIds: [UUID] = []
    private(set) var configuredBrowserManagers: [BrowserManager] = []
    private(set) var sceneActiveCallCount = 0
    private(set) var activateOwnerCallCount = 0
    private(set) var togglePlayPauseCallCount = 0
    private(set) var toggleMuteCallCount = 0

    var cardState: SumiBackgroundMediaCardState? {
        subject.value
    }

    var cardStatePublisher: AnyPublisher<SumiBackgroundMediaCardState?, Never> {
        subject.eraseToAnyPublisher()
    }

    func setFeatureEnabled(_ enabled: Bool) {
        featureEnabledValues.append(enabled)
    }

    func configure(browserManager: BrowserManager) {
        configuredBrowserManagers.append(browserManager)
    }

    func handleSceneActive() {
        sceneActiveCallCount += 1
    }

    func scheduleRefresh(delayNanoseconds: UInt64) {
        scheduledRefreshDelays.append(delayNanoseconds)
    }

    func handleTabActivated(_ tabId: UUID) {
        activatedTabIds.append(tabId)
    }

    func handleTabUnloaded(_ tabId: UUID) {
        unloadedTabIds.append(tabId)
    }

    func activateOwner() {
        activateOwnerCallCount += 1
    }

    func togglePlayPause() async {
        togglePlayPauseCallCount += 1
    }

    func toggleMute() async {
        toggleMuteCallCount += 1
    }
}

@MainActor
private final class FakeAutomaticBrowsingDataCleanupScheduler: BrowserAutomaticBrowsingDataCleanupScheduling {
    struct Schedule: Equatable {
        let retentionPeriod: SumiBrowsingDataRetentionPeriod
        let profileIds: [UUID]
        let currentProfileId: UUID?
        let force: Bool
        let reason: String
        let delayNanoseconds: UInt64?
    }

    private(set) var schedules: [Schedule] = []

    func scheduleIfNeeded(
        retentionPeriod: SumiBrowsingDataRetentionPeriod,
        historyManager: HistoryManager,
        profiles: [Profile],
        currentProfileId: UUID?,
        force: Bool,
        reason: String,
        delayNanoseconds: UInt64?
    ) {
        _ = historyManager
        schedules.append(
            Schedule(
                retentionPeriod: retentionPeriod,
                profileIds: profiles.map(\.id),
                currentProfileId: currentProfileId,
                force: force,
                reason: reason,
                delayNanoseconds: delayNanoseconds
            )
        )
    }
}

@MainActor
private final class FakeBrowserSiteDataPolicyService: BrowserSiteDataPolicyEnforcing {
    private(set) var enforcedURLs: [URL?] = []
    private(set) var enforcedProfileIds: [UUID?] = []
    private(set) var closedCleanupProfileIds: [UUID] = []

    func setBlockStorage(
        _ isEnabled: Bool,
        forHost host: String,
        profile: Profile?
    ) async {
        _ = (isEnabled, host, profile)
    }

    func setDeleteWhenAllWindowsClosed(
        _ isEnabled: Bool,
        forHost host: String,
        profile: Profile?
    ) {
        _ = (isEnabled, host, profile)
    }

    func enforceBlockStorageIfNeeded(for url: URL?, profile: Profile?) {
        enforcedURLs.append(url)
        enforcedProfileIds.append(profile?.id)
    }

    func performAllWindowsClosedCleanup(profiles: [Profile]) async {
        closedCleanupProfileIds = profiles.map(\.id)
    }
}

@MainActor
private final class FakeWebsiteDataCleanupService: SumiWebsiteDataCleanupServicing {
    func fetchCookies(in dataStore: WKWebsiteDataStore) async -> [HTTPCookie] {
        _ = dataStore
        return []
    }

    func fetchWebsiteDataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        _ = (dataTypes, dataStore)
        return []
    }

    func fetchSiteDataEntries(
        forDomain domain: String,
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [SumiSiteDataEntry] {
        _ = (domain, dataTypes, dataStore)
        return []
    }

    func removeCookies(
        _ selection: SumiCookieRemovalSelection,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = (selection, dataStore)
    }

    func removeWebsiteData(
        ofTypes dataTypes: Set<String>,
        modifiedSince date: Date,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = (dataTypes, date, dataStore)
    }

    func removeWebsiteDataForDomain(
        _ domain: String,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = (domain, includingCookies, dataStore)
    }

    func removeWebsiteDataForExactHost(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = (host, dataTypes, includingCookies, dataStore)
    }

    func removeWebsiteDataForDomains(
        _ domains: Set<String>,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {
        _ = (domains, dataTypes, includingCookies, dataStore)
    }

    func clearAllProfileWebsiteData(in dataStore: WKWebsiteDataStore) async {
        _ = dataStore
    }

    func removePersistentDataStore(forIdentifier identifier: UUID) async -> Bool {
        _ = identifier
        return true
    }

    func prunePersistentDataStores(keeping identifiersToKeep: Set<UUID>) async -> [UUID] {
        _ = identifiersToKeep
        return []
    }
}

@MainActor
private final class FakeBrowserFaviconService: BrowserFaviconServicing, HistoryFaviconCleaning, SumiBrowsingDataFaviconCleaning {
    private(set) var partitionProfileIds: [UUID?] = []
    private(set) var invalidatedSites: [(domain: String, profileId: UUID?)] = []
    private(set) var syncedShortcutPinURLs: [[URL]] = []
    private(set) var syncedBookmarkURLs: [[URL]] = []
    private(set) var syncedBookmarkPartitions: [SumiFaviconPartition] = []
    private(set) var clearedProfileIds: [UUID] = []
    private(set) var historyClearBurnCount = 0
    private(set) var historyBurnDomains: [Set<String>] = []
    private let partitionToReturn: SumiFaviconPartition?

    init(partitionToReturn: SumiFaviconPartition? = nil) {
        self.partitionToReturn = partitionToReturn
    }

    func partition(profile: Profile?) -> SumiFaviconPartition {
        partitionProfileIds.append(profile?.id)
        return partitionToReturn ?? .regular(profile?.id)
    }

    func invalidateSite(domain: String, profile: Profile?) {
        invalidatedSites.append((domain, profile?.id))
    }

    func invalidateSite(domain: String, partition: SumiFaviconPartition) {
        _ = partition
        invalidatedSites.append((domain, nil))
    }

    func syncShortcutPins(_ pins: [ShortcutPin]) {
        syncedShortcutPinURLs.append(pins.map(\.launchURL))
    }

    func syncBookmarks(
        _ bookmarks: [SumiBookmark],
        partition: SumiFaviconPartition
    ) {
        syncedBookmarkURLs.append(bookmarks.map(\.url))
        syncedBookmarkPartitions.append(partition)
    }

    func clearFaviconPartition(for profile: Profile) {
        clearedProfileIds.append(profile.id)
    }

    func burnAfterHistoryClear(savedLogins: Set<String>) async {
        _ = savedLogins
        historyClearBurnCount += 1
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>
    ) async {
        _ = (remainingHistoryHosts, savedLogins)
        historyBurnDomains.append(domains)
    }

#if DEBUG
    func drainRuntimeTasksForTests(cancel: Bool) async {
        _ = cancel
    }
#endif
}

@MainActor
private final class FakeBrowserVisitedLinkStore: BrowserVisitedLinkStoreManaging, HistoryVisitedLinkStoring {
    private(set) var replacedProfileIds: [UUID] = []
    private(set) var discardedProfileIds: [UUID] = []
    private(set) var appliedProfileIds: [UUID] = []
    private(set) var enabledRecordingCount = 0
    private(set) var recordedLinkURLs: [URL] = []
    private(set) var preloadedProfileIds: [UUID] = []

    func applyStore(to configuration: WKWebViewConfiguration, for profile: Profile) {
        _ = configuration
        appliedProfileIds.append(profile.id)
    }

    func applyStore(to configuration: WKWebViewConfiguration, profileId: UUID) {
        _ = configuration
        appliedProfileIds.append(profileId)
    }

    func applyStoreFromSourceIfAvailable(
        to configuration: WKWebViewConfiguration,
        source: WKWebViewConfiguration?
    ) {
        _ = (configuration, source)
    }

    func enableVisitedLinkRecording(on webView: WKWebView) {
        _ = webView
        enabledRecordingCount += 1
    }

    func recordVisitedLink(
        _ url: URL,
        for profile: Profile,
        sourceConfiguration: WKWebViewConfiguration?
    ) {
        _ = (profile, sourceConfiguration)
        recordedLinkURLs.append(url)
    }

    func preloadVisitedLinks(_ urls: [URL], for profileId: UUID) {
        _ = urls
        preloadedProfileIds.append(profileId)
    }

    func replaceVisitedLinks(_ urls: [URL], for profileId: UUID) {
        _ = urls
        replacedProfileIds.append(profileId)
    }

    func discardStore(for profileId: UUID) {
        discardedProfileIds.append(profileId)
    }
}

@MainActor
private final class FakeBrowsingDataCredentialStore: SumiBasicAuthCredentialCleaning {
    func allCredentialHosts() -> Set<String> {
        []
    }

    func deleteCredentials(
        profilePartitionId: UUID?,
        isEphemeralProfile: Bool?
    ) -> Bool {
        _ = (profilePartitionId, isEphemeralProfile)
        return true
    }
}

@MainActor
private final class FakeBrowserPrivacyService: BrowserPrivacyServicing {
    private(set) var clearCurrentPageCookiesCallCount = 0
    private(set) var hardReloadCurrentPageCallCount = 0

    func clearCurrentPageCookies(using context: BrowserPrivacyService.Context) {
        _ = context
        clearCurrentPageCookiesCallCount += 1
    }

    func hardReloadCurrentPage(using context: BrowserPrivacyService.Context) {
        _ = context
        hardReloadCurrentPageCallCount += 1
    }
}
