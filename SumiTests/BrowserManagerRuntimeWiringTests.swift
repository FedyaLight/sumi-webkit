import AppKit
import Combine
import Foundation
import WebKit
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class BrowserManagerRuntimeWiringTests: XCTestCase {
    func testShellWebViewAndSelectionRootsComposeWithoutRecursiveInitialization()
        throws {
        let browser = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )

        let shell = browser.shellRuntime
        let webViewRuntime = browser.webViewRuntime
        let selection = browser.browserTabSelection
        let splitFocus = browser.splitShortcutFocus
        let windowSessions = browser.windowSessionBundle
        let windowActivation = browser.windowActivation

        XCTAssertIdentical(shell.windowRegistry, browser.windowRegistry)
        XCTAssertIdentical(webViewRuntime.webViewSessions, browser.webViewSessions)
        XCTAssertIdentical(browser.splitWindowContext.query, browser.splitQuery)
        withExtendedLifetime(
            (selection, splitFocus, windowSessions, windowActivation)
        ) {}
    }

    func testBrowserManagerInitializationAttachesCoreRuntimeManagers() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        registry.enable(.boosts)
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        XCTAssertTrue(browserManager.optionalModules.boosts.isEnabled)
        XCTAssertTrue(browserManager.optionalModules.boosts.hasAttachedRuntime)
        XCTAssertFalse(browserManager.optionalModules.extensions.hasAttachedRuntime)
        XCTAssertFalse(browserManager.optionalModules.liveFolders.hasAttachedRuntime)
        XCTAssertFalse(browserManager.liveFolderManager.hasAttachedRuntime)
        XCTAssertTrue(compositorManagerCanUseAttachedRuntime(browserManager))
        XCTAssertNotNil(browserManager.runtimePortConnection.current)
        XCTAssertTrue(tabManagerRuntimeCanPrepareCreatedTabs(browserManager))
        XCTAssertTrue(splitServicesCanUseLiveRuntime(browserManager))
        XCTAssertFalse(
            browserManager.downloadManager.attachRetryTransport(
                TestDownloadRetryTransport()
            )
        )
        let boostsRuntimeAttached = await boostsModuleCanUseAttachedRuntime(browserManager)
        XCTAssertTrue(boostsRuntimeAttached)
        XCTAssertTrue(auxiliaryWindowServicesCanOpenPopup(browserManager))
        XCTAssertTrue(glanceRuntimeCanPreparePreviewTabs(browserManager))
        XCTAssertFalse(browserManager.optionalModules.extensions.hasLoadedRuntime)
    }

    func testDetachedRuntimeTabContextMenuForegroundOpenDoesNotUseActiveWindow() throws {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "Detached Runtime Source")
        let activeTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://active.example",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = activeTab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let detachedTab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://detached.example")!,
            loadsCachedFaviconOnInit: false
        )
        detachedTab.spaceId = space.id
        detachedTab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        let targetURL = URL(string: "https://detached-target.example")!
        let untrackedSource = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        untrackedSource.owningTab = detachedTab
        XCTAssertFalse(detachedTab.linkPresentationCommands.open(
            targetURL,
            from: untrackedSource,
            disposition: .newTab(selected: true)
        ))

        XCTAssertFalse(
            browserManager.tabCollectionMembershipOwner.allTabs().contains { $0.url == targetURL },
            "Detached tab runtime actions must not retarget through the active window."
        )
        XCTAssertEqual(windowState.currentTabId, activeTab.id)
    }

    func testTabSuspensionSelectedTabsDoNotUseGlobalCurrentTabFallback() throws {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        let selectedSpace = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "Selected")
        let selectedTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://selected.example",
            in: selectedSpace,
            activate: true
        )
        let staleSpace = installTestSpace(in: browserManager.spaceStateOwner, name: "Stale")
        let staleGlobalTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://stale.example",
            in: staleSpace,
            activate: false
        )

        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = selectedSpace.id
        windowState.currentTabId = selectedTab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        browserManager.tabStateStore.selection.replaceCurrentTab(staleGlobalTab)

        let suspensionRuntime = BrowserTabSuspensionRuntimeFactory.ports(
            windowRegistry: { windowRegistry },
            regularTabs: browserManager.tabCollectionMembershipOwner,
            lazyRestore: browserManager.lazyRestoreCoordinator,
            windowTabs: browserManager.shellRuntime.windowTabs,
            splitQuery: browserManager.splitWindowContext.query,
            webView: .inactive
        )
        let selectedTabIDs = suspensionRuntime.context.selectedTabIDs()

        XCTAssertEqual(selectedTabIDs, [selectedTab.id])
        XCTAssertFalse(selectedTabIDs.contains(staleGlobalTab.id))
    }

    func compositorManagerCanUseAttachedRuntime(_ browserManager: BrowserManager) -> Bool {
        let windowRegistry = browserManager.windowRegistry

        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "Compositor Runtime Wiring")
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/compositor",
            in: space,
            activate: true
        )
        tab.replaceUntrackedWebView(WKWebView())

        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        defer { windowRegistry.unregister(windowState.id) }

        browserManager.compositorManager.unloadTab(tab)
        return tab.resolvedCurrentWebView() != nil
    }

    func splitServicesCanUseLiveRuntime(
        _ browserManager: BrowserManager
    ) -> Bool {
        let windowRegistry = browserManager.windowRegistry

        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "Runtime Wiring")
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        defer { windowRegistry.unregister(windowState.id) }

        browserManager.splitEmptyCreation.create(in: windowState)
        return browserManager.splitWindowContext.query.group(in: windowState.id) != nil
    }

    func tabManagerRuntimeCanPrepareCreatedTabs(_ browserManager: BrowserManager) -> Bool {
        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "TabManager Runtime Wiring")
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/tab-manager-runtime",
            in: space,
            activate: false
        )
        return tab.hasBrowserRuntime && tab.sumiSettings === browserManager.sumiSettings
    }

    func boostsModuleCanUseAttachedRuntime(_ browserManager: BrowserManager) async -> Bool {
        let windowRegistry = browserManager.windowRegistry
        let trackedAdmission = browserManager.webViewRuntime.trackedWebViewAdmission

        let profileId = UUID()
        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "Boost Runtime Wiring", profileID: profileId)
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/boost",
            in: space,
            activate: true
        )
        tab.profileId = profileId
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = space.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        defer { windowRegistry.unregister(windowState.id) }

        let webView = FocusableWKWebView()
        webView.owningTab = tab
        trackedAdmission.registerAuxiliaryTrackedWebView(
            webView,
            for: tab,
            in: windowState.id
        )

        let started = await browserManager.optionalModules.boosts.startZapSelection(
            for: SumiBoost(profileId: profileId, host: "example.com"),
            tab: tab,
            windowState: windowState,
            isEphemeral: false,
            onSelector: { _ in /* No-op. */ },
            onFinish: { /* No-op. */ }
        )
        browserManager.optionalModules.boosts.stopZapSelection()
        return started
    }

    func auxiliaryWindowServicesCanOpenPopup(
        _ browserManager: BrowserManager
    ) -> Bool {
        let windowRegistry = browserManager.windowRegistry

        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "Auxiliary Runtime Wiring")
        let sourceTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/source",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = sourceTab.id
        windowRegistry.bindAppKitWindow(
            NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
            ),
            to: windowState
        )
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        defer { windowRegistry.unregister(windowState.id) }

        guard let webView = browserManager.auxiliaryWindows.popups.presentWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://example.com/popup")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: sourceTab,
            shouldActivateApp: false
        ) else {
            return false
        }
        let session = browserManager.auxiliaryWindows.sessions.session(for: webView)
        browserManager.auxiliaryWindows.teardownAuxiliaryWindowForTesting(webView, reason: .bulkCleanup)
        return session?.openerTab === sourceTab
            && session?.tab.isAuxiliaryMiniWindow == true
    }

    func glanceRuntimeCanPreparePreviewTabs(_ browserManager: BrowserManager) -> Bool {
        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "Glance Runtime Wiring")
        let sourceTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/glance-source",
            in: space,
            activate: true
        )

        browserManager.glanceManager.presentExternalURL(
            URL(string: "https://example.com/glance-preview")!,
            from: sourceTab
        )
        defer {
            browserManager.glanceManager.dismissGlance(persistsWindowSession: false)
        }

        guard let previewTab = browserManager.glanceManager.currentSession?.previewTab else {
            return false
        }
        return previewTab.hasBrowserRuntime
            && previewTab.sumiSettings === browserManager.sumiSettings
    }

    func testBrowserManagerInitializationRetainsInjectedPermissionRuntimeDependencies() throws {
        let container = try makeInMemoryStartupContainer()
        let permissionStore = DatabasePermissionStore(database: container)
        let recentActivityStore = SumiPermissionRecentActivityStore()
        let siteActivityStore = try makeSiteActivityStore()
        let indicatorEventStore = SumiPermissionIndicatorEventStore()
        let cleanupService = SumiPermissionCleanupService(
            store: permissionStore,
            recentActivityStore: recentActivityStore,
            antiAbuseStore: SumiPermissionAntiAbuseStore(
                persistenceAuthority: siteActivityStore.persistenceAuthority
            ),
            siteActivityStore: siteActivityStore
        )
        let blockedPopupStore = SumiBlockedPopupStore()
        let externalSchemeSessionStore = SumiExternalSchemeSessionStore()

        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: container),
            permissionIndicatorEventStore: indicatorEventStore,
            permissionRecentActivityStore: recentActivityStore,
            permissionSiteActivityStore: siteActivityStore,
            permissionCleanupService: cleanupService,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalSchemeSessionStore
        )

        XCTAssertIdentical(browserManager.permissionRuntime.permissionIndicatorEventStore, indicatorEventStore)
        XCTAssertIdentical(browserManager.permissionRuntime.permissionRecentActivityStore, recentActivityStore)
        XCTAssertIdentical(browserManager.permissionRuntime.permissionSiteActivityStore, siteActivityStore)
        XCTAssertIdentical(browserManager.permissionRuntime.permissionCleanupService, cleanupService)
        XCTAssertIdentical(browserManager.permissionRuntime.blockedPopupStore, blockedPopupStore)
        XCTAssertIdentical(browserManager.permissionRuntime.externalSchemeSessionStore, externalSchemeSessionStore)
        XCTAssertIdentical(browserManager.permissionRuntime.permissionBridges.permissionIndicatorEventStore, indicatorEventStore)
        XCTAssertIdentical(browserManager.permissionRuntime.permissionBridges.blockedPopupStore, blockedPopupStore)
        XCTAssertIdentical(browserManager.permissionRuntime.permissionBridges.externalSchemeSessionStore, externalSchemeSessionStore)
    }

    func testMissingPermissionStoreCreatesDistinctMemoryOnlyAuthorities() throws {
        let firstBrowserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        let secondBrowserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )

        XCTAssertFalse(
            firstBrowserManager.permissionRuntime.permissionSiteActivityStore.persistenceAuthority
                === secondBrowserManager.permissionRuntime.permissionSiteActivityStore.persistenceAuthority
        )
    }

    func testBrowserManagerPermissionFacadesRouteThroughScopedBridgeRegistry() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let registry = browserManager.permissionRuntime.permissionBridges

        XCTAssertIdentical(browserManager.permissionRuntime.permissionBridges, registry)
        XCTAssertIdentical(browserManager.permissionRuntime.webKitPermissionBridge, registry.webKitPermissionBridge)
        XCTAssertIdentical(browserManager.permissionRuntime.webKitGeolocationBridge, registry.webKitGeolocationBridge)
        XCTAssertIdentical(browserManager.permissionRuntime.notificationPermissionBridge, registry.notificationPermissionBridge)
        XCTAssertIdentical(browserManager.permissionRuntime.filePickerPermissionBridge, registry.filePickerPermissionBridge)
        XCTAssertIdentical(browserManager.permissionRuntime.storageAccessPermissionBridge, registry.storageAccessPermissionBridge)
        XCTAssertIdentical(browserManager.permissionRuntime.popupPermissionBridge, registry.popupPermissionBridge)
        XCTAssertIdentical(browserManager.permissionRuntime.externalSchemePermissionBridge, registry.externalSchemePermissionBridge)
        XCTAssertIdentical(browserManager.permissionRuntime.permissionLifecycleController, registry.permissionLifecycleController)
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
            startupPersistence: BrowserManagerStartupPersistence(database: container),
            systemPermissionService: systemPermissionService,
            permissionCoordinator: permissionCoordinator,
            permissionSiteActivityStore: siteActivityStore,
            blockedPopupStore: blockedPopupStore,
            permissionBridgeOverrides: BrowserPermissionBridgeRegistry.Overrides(
                popupPermissionBridge: popupBridge
            )
        )

        XCTAssertIdentical(browserManager.permissionRuntime.permissionBridges.popupPermissionBridge, popupBridge)
        XCTAssertIdentical(browserManager.permissionRuntime.popupPermissionBridge, popupBridge)
        XCTAssertIdentical(browserManager.permissionRuntime.permissionBridges.blockedPopupStore, blockedPopupStore)
    }

    func testCanonicalWebViewRuntimeWiresInjectedBrowsingDataCleanupService() throws {
        let cleanupService = makeBrowsingDataCleanupService()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            browsingDataCleanupService: cleanupService,
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let preparer = try XCTUnwrap(cleanupService.destructiveCleanupPreparer)
        XCTAssertIdentical(
            preparer as AnyObject,
            browserManager.webViewRuntime.websiteDataCleanupService
        )
    }

    func testCanonicalWebViewRuntimePreparesVisibleWebViewsThroughBrowserManager() async throws {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        await browserManager.drainProtectionRuntimeTasksForTests()

        let space = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(in: browserManager.spaceStateOwner, name: "Visible WebView Runtime")
        let tab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/visible-webview",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        XCTAssertTrue(browserManager.shellRuntime.windowVisuals.prepareVisibleWebViews(for: windowState))
        let materialized = try XCTUnwrap(
            browserManager.webViewRuntime.ownershipQuery.webView(
                for: tab.id,
                in: windowState.id
            )
        )
        let runtimePorts = try XCTUnwrap(browserManager.runtimePortConnection.current)

        runtimePorts.webViewLifecycle.materializeVisibleTabWebViewIfNeeded(
            tab,
            in: windowState
        )

        XCTAssertIdentical(
            browserManager.webViewRuntime.ownershipQuery.webView(
                for: tab.id,
                in: windowState.id
            ),
            materialized
        )
    }

    func testBrowserManagerCreatesOneCanonicalWebViewRuntimeWithUsableServices() throws {
        let cleanupService = makeBrowsingDataCleanupService()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            ),
            browsingDataCleanupService: cleanupService,
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let webViewRuntime = browserManager.webViewRuntime
        let resolvedAgain = browserManager.testWebViewRuntime()

        XCTAssertIdentical(webViewRuntime, resolvedAgain)
        XCTAssertIdentical(
            webViewRuntime.webViewSessions,
            browserManager.webViewSessions
        )
        XCTAssertIdentical(
            cleanupService.destructiveCleanupPreparer as AnyObject,
            webViewRuntime.websiteDataCleanupService
        )

        let tab = Tab(
            webViewSessions: browserManager.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let windowID = UUID()
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        webViewRuntime.trackedWebViewAdmission.registerAuxiliaryTrackedWebView(
            webView,
            for: tab,
            in: windowID
        )
        XCTAssertIdentical(
            webViewRuntime.ownershipQuery.webView(for: tab.id, in: windowID),
            webView
        )

        webViewRuntime.lifecycleService.cleanupWindow(windowID)

        XCTAssertNil(
            webViewRuntime.ownershipQuery.webView(for: tab.id, in: windowID)
        )
    }

    func testSessionSideEffectsPortRetainsExactProcessServices() throws {
        let browserManager = BrowserManager()
        let runtimePorts = try XCTUnwrap(browserManager.runtimePortConnection.current)
        let tab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com/closed")!,
            loadsCachedFaviconOnInit: false
        )

        runtimePorts.captureClosedTab(tab, sourceSpaceId: nil)

        guard case .tab(let closedTab) = browserManager.recentlyClosedManager.mostRecentItem else {
            return XCTFail("Expected the exact process recently-closed service to receive the item")
        }
        XCTAssertEqual(closedTab.url, tab.url)
        XCTAssertIdentical(
            runtimePorts.notifications() as AnyObject,
            browserManager.notificationPresenter
        )
    }

    func testWindowQueryPortTracksTheExactInjectedShellRegistry() throws {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        let runtimePorts = try XCTUnwrap(browserManager.runtimePortConnection.current)
        let firstWindow = BrowserWindowState()
        windowRegistry.register(firstWindow)

        XCTAssertIdentical(runtimePorts.windowState(for: firstWindow.id), firstWindow)

        let replacementWindow = BrowserWindowState()
        windowRegistry.unregister(firstWindow.id)
        windowRegistry.register(replacementWindow)

        XCTAssertNil(runtimePorts.windowState(for: firstWindow.id))
        XCTAssertIdentical(
            runtimePorts.windowState(for: replacementWindow.id),
            replacementWindow
        )
    }

    func testShellRuntimeWindowRegistryBindingUpdatesDependentRuntimeManagers() throws {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
        XCTAssertIdentical(browserManager.windowRegistry, windowRegistry)
        XCTAssertIdentical(browserManager.glanceManager.windowRegistry, windowRegistry)
        let selectedTabID = UUID()
        let windowState = BrowserWindowState()
        windowState.currentTabId = selectedTabID
        windowRegistry.register(windowState)
        browserManager.splitWindowContext.previews.begin(
            targetRect: nil,
            style: .edge,
            in: windowState.id
        )
        XCTAssertEqual(
            browserManager.splitWindowContext.query.visibleTabIDs(in: windowState.id),
            [selectedTabID]
        )
    }

    func testShellRuntimeOwnsConstructorInjectedWindowRegistryForItsLifetime() throws {
        var browserManager: BrowserManager?
        weak var retainedRegistry: WindowRegistry?

        do {
            let windowRegistry = WindowRegistry()
            retainedRegistry = windowRegistry
            browserManager = BrowserManager(
                windowRegistry: windowRegistry,
                startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
                )
            )
        }

        XCTAssertNotNil(retainedRegistry)
        XCTAssertIdentical(browserManager?.windowRegistry, retainedRegistry)

        browserManager = nil

        XCTAssertNil(retainedRegistry)
    }

    func makeBrowsingDataCleanupService() -> SumiBrowsingDataCleanupService {
        SumiBrowsingDataCleanupService(
            websiteDataCleanupService: BrowserManagerWebsiteDataCleanupServiceStub(),
            faviconCacheCleaner: BrowserManagerFaviconServiceStub(),
            appResidueCleaner: SumiBrowsingDataAppResidueCleaner(),
            basicAuthCredentialStore: FakeBrowsingDataCredentialStore(),
            visitedLinkStore: FakeBrowserVisitedLinkStore()
        )
    }

    func makeSiteDataPolicyStore() throws -> SumiSiteDataPolicyStore {
        SumiSiteDataPolicyStore(database: try SumiDatabase.inMemory())
    }

    func makeInMemoryStartupContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }

    func makeSiteActivityStore() throws -> SumiPermissionSiteActivityStore {
        SumiPermissionSiteActivityStore()
    }
}

@MainActor
final class FakeNativeNowPlayingController: SumiNativeNowPlayingRuntimeControlling {
    var cardStates: [SumiBackgroundMediaCardState] = []
    private(set) var featureEnabledValues: [Bool] = []
    private(set) var scheduledRefreshDelays: [UInt64] = []
    private(set) var activatedTabIds: [UUID] = []
    private(set) var unloadedTabIds: [UUID] = []
    private(set) var configuredContextCount = 0
    private(set) var activateOwnerCallCount = 0
    private(set) var togglePlayPauseCallCount = 0
    private(set) var toggleMuteCallCount = 0
    private(set) var togglePictureInPictureCallCount = 0

    func setFeatureEnabled(_ enabled: Bool) {
        featureEnabledValues.append(enabled)
    }

    func configure(context _: SumiNativeNowPlayingRuntimeContext) {
        configuredContextCount += 1
    }

    func scheduleRefresh(delayNanoseconds: UInt64) {
        scheduledRefreshDelays.append(delayNanoseconds)
    }

    func handleTabActivated(_ tabId: UUID, in _: UUID) {
        activatedTabIds.append(tabId)
    }

    func handleTabUnloaded(_ tabId: UUID) {
        unloadedTabIds.append(tabId)
    }

    func activateOwner(cardID _: SumiBackgroundMediaCardID) {
        activateOwnerCallCount += 1
    }

    func togglePlayPause(cardID _: SumiBackgroundMediaCardID) async {
        togglePlayPauseCallCount += 1
    }

    func toggleMute(cardID _: SumiBackgroundMediaCardID) async {
        toggleMuteCallCount += 1
    }

    func togglePictureInPicture(cardID _: SumiBackgroundMediaCardID) async {
        togglePictureInPictureCallCount += 1
    }

    func dismiss(cardID _: SumiBackgroundMediaCardID) async {}
}

@MainActor
final class FakeBrowsingDataCleanupScheduler: BrowsingDataCleanupScheduling {
    struct Schedule: Equatable {
        let retentionPeriod: SumiBrowsingDataRetentionPeriod
        let profileIds: [UUID]
        let currentProfileId: UUID?
        let force: Bool
        let reason: String
        let delayNanoseconds: UInt64?
    }

    private(set) var schedules: [Schedule] = []

    func attachDestructiveCleanupPreparer(
        _ preparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    ) {
        _ = preparer
    }

    func scheduleIfNeeded(_ request: SumiBrowsingDataCleanupScheduleRequest) {
        _ = request.historyManager
        schedules.append(
            Schedule(
                retentionPeriod: request.retentionPeriod,
                profileIds: request.profiles.map(\.id),
                currentProfileId: request.currentProfileId,
                force: request.force,
                reason: request.reason,
                delayNanoseconds: request.delayNanoseconds
            )
        )
    }
}

@MainActor
final class FakeBrowserSiteDataPolicyService: BrowserSiteDataPolicyEnforcing {
    private(set) var enforcedURLs: [URL?] = []
    private(set) var enforcedProfileIds: [UUID?] = []

    func attachDestructiveCleanupPreparer(
        _ preparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    ) {
        _ = preparer
    }
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
final class BrowserManagerWebsiteDataCleanupServiceStub: SumiWebsiteDataCleanupServicing {
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
final class BrowserManagerFaviconServiceStub:
    BrowserFaviconServicing,
    BrowserFaviconImageReading,
    BrowserFaviconLiveDiscoveryIngesting,
    BrowserFaviconLocalIconIngesting,
    BrowserFaviconPrefetchScheduling,
    HistoryFaviconCleaning,
    SumiBrowsingDataFaviconCleaning {
    private(set) var partitionProfileIds: [UUID?] = []
    private(set) var invalidatedSites: [(domain: String, profileId: UUID?)] = []
    private(set) var syncedShortcutPinURLs: [[URL]] = []
    private(set) var syncedBookmarkURLs: [[URL]] = []
    private(set) var syncedBookmarkPartitions: [SumiFaviconPartition] = []
    private(set) var clearedProfileIds: [UUID] = []
    private(set) var historyClearBurnCount = 0
    private(set) var historyBurnDomains: [Set<String>] = []
    let partitionToReturn: SumiFaviconPartition?

    init(partitionToReturn: SumiFaviconPartition? = nil) {
        self.partitionToReturn = partitionToReturn
    }

    var capabilities: BrowserFaviconCapabilities {
        BrowserFaviconCapabilities(
            images: self,
            liveDiscovery: self,
            localIconIngestion: self,
            prefetch: self
        )
    }

    nonisolated func cachedPreparedImage(for _: SumiPreparedFaviconRequest) -> NSImage? { nil }
    nonisolated func cachedSelection(
        for _: URL,
        partition _: SumiFaviconPartition
    ) -> SumiStoredFaviconSelection? { nil }
    nonisolated func preparedImage(
        for _: SumiPreparedFaviconRequest,
        priority _: SumiFaviconFetchPriority,
        scheduleFetchOnMiss _: Bool
    ) async -> NSImage? { nil }
    func ingestVisibleTabDiscovery(
        links _: [SumiFaviconDiscoveredLink],
        documentURL _: URL,
        baseURL _: URL?,
        partition _: SumiFaviconPartition,
        webView _: WKWebView?,
        aliasPageURLs _: [URL]
    ) async -> NSImage? { nil }
    nonisolated func ingestLocalExtensionIcon(
        fileURL _: URL,
        documentURL _: URL,
        partition _: SumiFaviconPartition,
        context _: SumiFaviconDisplayContext
    ) async -> NSImage? { nil }
    nonisolated func ingestImportedIcon(
        payload _: Data,
        iconURL _: URL,
        documentURL _: URL,
        partition _: SumiFaviconPartition
    ) async {}
    nonisolated func scheduleColdFetch(
        for _: URL,
        partition _: SumiFaviconPartition,
        priority _: SumiFaviconFetchPriority
    ) {}

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
final class FakeBrowserVisitedLinkStore: BrowserVisitedLinkStoreManaging, HistoryVisitedLinkStoring {
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
final class FakeBrowsingDataCredentialStore: SumiBasicAuthCredentialCleaning {
    func allCredentialHosts() -> Set<String> {
        []
    }

    func deleteCredentials(
        profilePartitionId: UUID?,
        // nil means the cleanup scope includes both regular and ephemeral profile credentials.
        // swiftlint:disable:next discouraged_optional_boolean
        isEphemeralProfile: Bool?
    ) -> Bool {
        _ = (profilePartitionId, isEphemeralProfile)
        return true
    }
}

@MainActor
final class FakeBrowserPrivacyService: BrowserPrivacyServicing {
    private(set) var clearCurrentPageCookiesCallCount = 0
    private(set) var hardReloadCurrentPageCallCount = 0

    func attachDestructiveCleanupPreparer(
        _ preparer: (any SumiDestructiveBrowsingDataCleanupPreparing)?
    ) {
        _ = preparer
    }

    func clearCurrentPageCookies(using context: BrowserPrivacyService.Context) {
        _ = context
        clearCurrentPageCookiesCallCount += 1
    }

    func hardReloadCurrentPage(using context: BrowserPrivacyService.Context) {
        _ = context
        hardReloadCurrentPageCallCount += 1
    }
}
