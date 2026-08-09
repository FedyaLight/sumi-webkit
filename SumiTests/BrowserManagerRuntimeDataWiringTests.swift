import AppKit
import Combine
import Foundation
import WebKit
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
extension BrowserManagerRuntimeWiringTests {
    func testBrowserManagerRuntimeDataServicesUseInjectedBundle() async throws {
        let browsingDataCleanupService = makeBrowsingDataCleanupService()
        let automaticCleanupService = FakeBrowsingDataCleanupScheduler()
        let siteDataPolicyService = FakeBrowserSiteDataPolicyService()
        let faviconService = BrowserManagerFaviconServiceStub()
        let visitedLinkStore = FakeBrowserVisitedLinkStore()
        let privacyService = FakeBrowserPrivacyService()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            dataServices: BrowserManagerDataServices(
                websiteDataCleanupService: BrowserManagerWebsiteDataCleanupServiceStub(),
                browsingDataCleanupService: browsingDataCleanupService,
                automaticBrowsingDataCleanupService: automaticCleanupService,
                siteDataPolicyStore: try makeSiteDataPolicyStore(),
                siteDataPolicyEnforcementService: siteDataPolicyService,
                faviconService: faviconService,
                faviconCapabilities: faviconService.capabilities,
                visitedLinkStore: visitedLinkStore,
                historyFaviconCleaner: faviconService,
                historyVisitedLinkStore: visitedLinkStore,
                privacyService: privacyService
            ),
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        browserManager.startRuntimeAfterStartupRecovery()
        let initialProfile = try XCTUnwrap(browserManager.currentProfile)

        XCTAssertIdentical(browserManager.browsingDataCleanupService, browsingDataCleanupService)
        XCTAssertEqual(faviconService.partitionProfileIds, [initialProfile.id])

        let tab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/path")!,
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        XCTAssertIdentical(tab.faviconService as AnyObject, faviconService)
        XCTAssertIdentical(tab.faviconCapabilities.images as AnyObject, faviconService)
        XCTAssertIdentical(tab.visitedLinkStore as AnyObject, visitedLinkStore)

        browserManager.dataServices.siteDataPolicyEnforcementService.enforceBlockStorageIfNeeded(
            for: tab.url,
            profile: tab.resolveProfile()
        )

        XCTAssertEqual(siteDataPolicyService.enforcedURLs, [tab.url])
        XCTAssertEqual(siteDataPolicyService.enforcedProfileIds, [initialProfile.id])

        await browserManager.dataServices.siteDataPolicyEnforcementService.performAllWindowsClosedCleanup(
            profiles: browserManager.profileManager.profiles
        )

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

        browserManager.privacyBundle.automaticBrowsingDataCleanup.schedule(
            reason: "unit-test",
            force: true,
            delayNanoseconds: 0
        )

        XCTAssertEqual(automaticCleanupService.schedules.count, 2)
        XCTAssertTrue(automaticCleanupService.schedules[1].force)
        XCTAssertEqual(automaticCleanupService.schedules[1].reason, "unit-test")
        XCTAssertEqual(automaticCleanupService.schedules[1].delayNanoseconds, 0)

        // Re-assigning settings preserves the didSet attachment workflow.
        browserManager.sumiSettings = settings

        XCTAssertEqual(automaticCleanupService.schedules.count, 3)
        XCTAssertEqual(automaticCleanupService.schedules[2].reason, "settings-attached")

        // Retention-change notifications route through the live runtime
        // lifecycle into the automatic cleanup owner.
        NotificationCenter.default.post(
            name: .sumiBrowsingDataRetentionChanged,
            object: nil
        )
        for _ in 0..<25 where automaticCleanupService.schedules.count < 4 {
            await Task.yield()
        }

        XCTAssertEqual(automaticCleanupService.schedules.count, 4)
        XCTAssertEqual(automaticCleanupService.schedules[3].reason, "retention-setting-changed")
        XCTAssertTrue(automaticCleanupService.schedules[3].force)
        XCTAssertEqual(automaticCleanupService.schedules[3].delayNanoseconds, 0)

        await browserManager.historyManager.clearAll()

        XCTAssertEqual(faviconService.historyClearBurnCount, 1)
    }

    func testBrowserManagerDeinitShutsDownRuntimeLifecycleAgainstLiveSubsystems() async throws {
        let automaticCleanupService = FakeBrowsingDataCleanupScheduler()
        let faviconService = BrowserManagerFaviconServiceStub()
        let visitedLinkStore = FakeBrowserVisitedLinkStore()
        var browserManager: BrowserManager? = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            dataServices: BrowserManagerDataServices(
                websiteDataCleanupService: BrowserManagerWebsiteDataCleanupServiceStub(),
                browsingDataCleanupService: makeBrowsingDataCleanupService(),
                automaticBrowsingDataCleanupService: automaticCleanupService,
                siteDataPolicyStore: try makeSiteDataPolicyStore(),
                siteDataPolicyEnforcementService: FakeBrowserSiteDataPolicyService(),
                faviconService: faviconService,
                faviconCapabilities: faviconService.capabilities,
                visitedLinkStore: visitedLinkStore,
                historyFaviconCleaner: faviconService,
                historyVisitedLinkStore: visitedLinkStore,
                privacyService: FakeBrowserPrivacyService()
            ),
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        browserManager?.startRuntimeAfterStartupRecovery()

        let suiteName = "BrowserManagerDeinitShutdownTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(
            SumiBrowsingDataRetentionPeriod.sevenDays.rawValue,
            forKey: "settings.browsingData.retentionDays"
        )
        let settings = SumiSettingsService(userDefaults: defaults)
        browserManager?.sumiSettings = settings
        XCTAssertEqual(automaticCleanupService.schedules.count, 1)

        let permissionRuntime = try XCTUnwrap(browserManager?.permissionRuntime)
        XCTAssertTrue(permissionRuntime.isObservingPermissionEvents)

        weak var releasedBrowserManager = browserManager
        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertFalse(permissionRuntime.isObservingPermissionEvents)

        // A retention change after teardown must not schedule new cleanup work.
        NotificationCenter.default.post(
            name: .sumiBrowsingDataRetentionChanged,
            object: nil
        )
        for _ in 0..<10 {
            await Task.yield()
        }

        XCTAssertEqual(automaticCleanupService.schedules.count, 1)
    }

    func testRetainedAttachedTabDoesNotRetainBrowserRuntimeRoots() throws {
        var windowRegistry: WindowRegistry? = WindowRegistry()
        var browserManager: BrowserManager? = BrowserManager(
            windowRegistry: try XCTUnwrap(windowRegistry),
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        let tab: Tab
        let installation: UntrackedWebViewInstallationService
        do {
            let manager = try XCTUnwrap(browserManager)
            tab = Tab(
                webViewSessions: manager.webViewSessions,
                loadsCachedFaviconOnInit: false
            )
            tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: manager))
            installation = manager.webViewRuntime
                .untrackedWebViewInstallationService
        }
        weak var releasedBrowserManager = browserManager
        weak var releasedWindowRegistry = windowRegistry

        browserManager = nil
        windowRegistry = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNil(releasedWindowRegistry)
        XCTAssertTrue(tab.hasBrowserRuntime)

        let lateCandidate = WKWebView()
        XCTAssertEqual(
            installation.installUntracked(lateCandidate, for: tab),
            .rejected(
                .runtimeTabIdentityConflict,
                webViewDisposition: .callerMustDestroy
            )
        )
        XCTAssertNil(tab.webViewSession.residence(of: lateCandidate))
    }

    func testNativeSurfaceViewModelsUseInjectedFaviconService() throws {
        let injectedPartition = SumiFaviconPartition(
            profileIdentifier: "injected-view-models",
            isPrivate: true
        )
        let browsingDataCleanupService = makeBrowsingDataCleanupService()
        let faviconService = BrowserManagerFaviconServiceStub(partitionToReturn: injectedPartition)
        let visitedLinkStore = FakeBrowserVisitedLinkStore()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            dataServices: BrowserManagerDataServices(
                websiteDataCleanupService: BrowserManagerWebsiteDataCleanupServiceStub(),
                browsingDataCleanupService: browsingDataCleanupService,
                automaticBrowsingDataCleanupService: FakeBrowsingDataCleanupScheduler(),
                siteDataPolicyStore: try makeSiteDataPolicyStore(),
                siteDataPolicyEnforcementService: FakeBrowserSiteDataPolicyService(),
                faviconService: faviconService,
                faviconCapabilities: faviconService.capabilities,
                visitedLinkStore: visitedLinkStore,
                historyFaviconCleaner: faviconService,
                historyVisitedLinkStore: visitedLinkStore,
                privacyService: FakeBrowserPrivacyService()
            ),
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let initialProfile = try XCTUnwrap(browserManager.currentProfile)

        let historyViewModel = HistoryPageViewModel(
            browserContext: WebsiteViewContextFactory.historyPageBrowserContext(for: browserManager),
            windowState: nil
        )
        let bookmarksViewModel = SumiBookmarksPageViewModel(
            browserContext: WebsiteViewContextFactory.bookmarksPageBrowserContext(for: browserManager),
            windowState: nil
        )

        XCTAssertEqual(historyViewModel.faviconPartition, injectedPartition)
        XCTAssertEqual(bookmarksViewModel.faviconPartition, injectedPartition)
        XCTAssertIdentical(historyViewModel.faviconImageReader as AnyObject, faviconService)
        XCTAssertIdentical(bookmarksViewModel.faviconImageReader as AnyObject, faviconService)
        XCTAssertEqual(
            faviconService.partitionProfileIds,
            [initialProfile.id, initialProfile.id, initialProfile.id]
        )
    }

    func testSettingsPageBrowserContextProjectsBrowserSubsystemsWithoutSettingsUICoupling() throws {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let profile = Profile(name: "Settings Context")
        let space = Space(name: "Settings Context", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let browserContext = WebsiteViewContextFactory.settingsPageBrowserContext(
            for: browserManager
        )

        XCTAssertTrue(browserContext.profileManager === browserManager.profileManager)
        XCTAssertEqual(
            browserContext.profileInventory.snapshot()[profile.id] ?? .none,
            ProfileUsage(spaces: 1, tabs: 0)
        )
        XCTAssertTrue(browserContext.extensionsModule === browserManager.optionalModules.extensions)
        XCTAssertTrue(
            browserContext.extensionSurfaceStore === browserManager.optionalModules.extensions.surfaceStore
        )
        XCTAssertEqual(browserContext.currentProfile()?.id, profile.id)

        var inventoryUpdateCount = 0
        let inventoryUpdates = browserContext.profileInventory.updates.sink {
            inventoryUpdateCount += 1
        }
        _ = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://settings-inventory.example",
            in: space,
            activate: false
        )
        XCTAssertEqual(inventoryUpdateCount, 1)
        XCTAssertEqual(
            browserContext.profileInventory.snapshot()[profile.id]?.tabs,
            1
        )
        let profilePin = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: profile.id,
            index: 0,
            launchURL: URL(string: "https://profile-pin.example")!,
            title: "Profile Pin"
        )
        browserManager.shortcutPinCollectionStateOwner
            .replacePinnedByProfile([profile.id: [profilePin]])
        XCTAssertEqual(
            browserContext.profileInventory.snapshot()[profile.id],
            ProfileUsage(spaces: 1, tabs: 2)
        )

        var browserManagerChangeCount = 0
        var publishedProfileIDs: [UUID?] = []
        let browserManagerChanges = browserManager.objectWillChange.sink {
            browserManagerChangeCount += 1
        }
        let currentProfileChanges = browserManager.currentProfileAuthority
            .$currentProfile
            .sink { publishedProfileIDs.append($0?.id) }
        let replacementProfile = Profile(name: "Replacement Settings Context")

        browserManager.currentProfile = replacementProfile

        XCTAssertEqual(browserManagerChangeCount, 1)
        XCTAssertEqual(
            publishedProfileIDs,
            [profile.id, replacementProfile.id]
        )
        XCTAssertIdentical(
            browserManager.currentProfileAuthority.currentProfile,
            replacementProfile
        )
        XCTAssertEqual(
            browserManager.runtimePortConnection.current?.currentProfileId,
            replacementProfile.id
        )
        XCTAssertIdentical(browserContext.currentProfile(), replacementProfile)
        withExtendedLifetime(
            (browserManagerChanges, currentProfileChanges, inventoryUpdates)
        ) {}

        let repository = browserContext.makePermissionRepository()
        XCTAssertNotNil(repository)
    }

    func testSelectionPublicationPreservesLazyExtensionRuntime() throws {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let profile = try XCTUnwrap(
            browserManager.currentProfileAuthority.currentProfile
        )
        let space = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Lazy Extension Selection",
            profileID: profile.id
        )
        let windowState = BrowserWindowState()
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            in: space,
            activate: false
        )
        browserManager.optionalModules.extensions.notifyWindowOpenedIfLoaded(windowState)
        browserManager.optionalModules.extensions.notifyWindowFocusedIfLoaded(windowState)
        let inactivePreparation = browserManager.optionalModules.extensions
            .prepareInitialTabExtensionPublication(
                window: windowState,
                tab: tab,
                webView: FocusableWKWebView(),
                reason: "testSelectionPublicationPreservesLazyExtensionRuntime"
            )
        XCTAssertTrue(
            browserManager.selectTab(tab, in: windowState).wasCommitted
        )
        browserManager.optionalModules.extensions.notifyTabClosedIfLoaded(tab)

        XCTAssertFalse(browserManager.optionalModules.extensions.hasLoadedRuntime)
        guard case .notParticipating = inactivePreparation else {
            return XCTFail("An unloaded extension module must not participate")
        }
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
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            nowPlayingController: nowPlayingController,
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let tab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/video")!,
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        tab.applyAudioState(.unmuted(isPlayingAudio: true))

        XCTAssertEqual(nowPlayingController.scheduledRefreshDelays, [0])

        tab.unloadWebView()

        XCTAssertEqual(nowPlayingController.unloadedTabIds, [tab.id])
        XCTAssertEqual(nowPlayingController.scheduledRefreshDelays, [0, 0])
    }

}
