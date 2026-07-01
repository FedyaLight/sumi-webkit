import Combine
import Foundation
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
        browserManager.webViewCoordinator = WebViewCoordinator()

        XCTAssertTrue(compositorManagerCanUseAttachedRuntime(browserManager))
        XCTAssertNotNil(browserManager.tabManager.runtimeContext)
        XCTAssertTrue(tabManagerRuntimeCanPrepareCreatedTabs(browserManager))
        XCTAssertTrue(splitManagerCanUseAttachedRuntime(browserManager))
        XCTAssertTrue(downloadRetryRuntimeCanResolveWindowOwnedWebView(browserManager))
        XCTAssertTrue(boostsModuleCanUseAttachedRuntime(browserManager))
        XCTAssertTrue(auxiliaryWindowManagerCanUseAttachedRuntime(browserManager))
        XCTAssertTrue(glanceRuntimeCanPreparePreviewTabs(browserManager))
        XCTAssertFalse(browserManager.extensionsModule.hasLoadedRuntime)
        XCTAssertFalse(browserManager.userscriptsModule.hasLoadedRuntime)
    }

    func testTabRuntimeCompositionServiceAttachesResourceRuntimesAndHandlesStructuralChanges() async throws {
        let structuralChanges = PassthroughSubject<Void, Never>()
        let coordinator = WebViewCoordinator()
        let visibleWindowID = UUID()
        let selectedTabID = UUID()
        let visibleTabID = UUID()
        let tab = Tab(
            url: URL(string: "https://example.com/runtime-composition")!,
            loadsCachedFaviconOnInit: false
        )
        let previousTab = Tab(
            url: URL(string: "https://example.com/previous")!,
            loadsCachedFaviconOnInit: false
        )

        var attachedTabSuspensionRuntime: TabSuspensionRuntime?
        var attachedBackgroundMediaRuntime: SumiBackgroundMediaOptimizationRuntime?
        var tabStructuralRevisionCount = 0
        var tabSuspensionReconcileReasons: [String] = []
        var backgroundMediaReconcileReasons: [String] = []
        var refreshedLazyRestoreContexts: [TabSuspensionEvaluationContext] = []
        var activatedTabs: [(new: UUID, previous: UUID?)] = []
        let structuralChangeHandled = expectation(description: "structural change handled")

        let dependencies = BrowserTabRuntimeCompositionService.Dependencies(
            attachTabSuspensionRuntime: { runtime in
                attachedTabSuspensionRuntime = runtime
            },
            attachBackgroundMediaOptimizationRuntime: { runtime in
                attachedBackgroundMediaRuntime = runtime
            },
            tabStructuralChanges: structuralChanges.eraseToAnyPublisher(),
            incrementTabStructuralRevision: {
                tabStructuralRevisionCount += 1
                structuralChangeHandled.fulfill()
            },
            scheduleTabSuspensionReconcile: { reason in
                tabSuspensionReconcileReasons.append(reason)
            },
            scheduleBackgroundMediaReconcile: { reason in
                backgroundMediaReconcileReasons.append(reason)
            },
            webViewCoordinator: {
                coordinator
            },
            memoryMode: {
                .custom
            },
            customDeactivationDelay: {
                42
            },
            tabEnergySaverActive: {
                false
            },
            backgroundMediaEnergySaverActive: {
                true
            },
            allKnownTabs: {
                [tab]
            },
            selectedTabIDs: {
                [selectedTabID]
            },
            tabSuspensionVisibleTabIDsByWindow: {
                [visibleWindowID: [visibleTabID]]
            },
            backgroundMediaVisibleTabIDsByWindow: {
                [visibleWindowID: [visibleTabID]]
            },
            refreshLazyRestoreQueue: { context in
                refreshedLazyRestoreContexts.append(context)
            },
            notifyTabActivatedIfLoaded: { newTab, previousTab in
                activatedTabs.append((newTab.id, previousTab?.id))
            }
        )

        let cancellable = BrowserTabRuntimeCompositionService.attach(
            dependencies: dependencies
        )
        defer {
            cancellable.cancel()
        }

        let tabSuspensionRuntime = try XCTUnwrap(attachedTabSuspensionRuntime)
        XCTAssertIdentical(tabSuspensionRuntime.webViewCoordinator(), coordinator)
        XCTAssertEqual(tabSuspensionRuntime.memoryMode(), .custom)
        XCTAssertEqual(tabSuspensionRuntime.customDeactivationDelay(), 42)
        XCTAssertFalse(tabSuspensionRuntime.energySaverActive())
        XCTAssertEqual(tabSuspensionRuntime.allKnownTabs().map(\.id), [tab.id])
        XCTAssertEqual(tabSuspensionRuntime.selectedTabIDs(), [selectedTabID])
        XCTAssertEqual(
            tabSuspensionRuntime.visibleTabIDsByWindow(),
            [visibleWindowID: [visibleTabID]]
        )

        let lazyRestoreContext = TabSuspensionEvaluationContext(
            visibleTabIDs: [visibleTabID],
            selectedTabIDs: [selectedTabID],
            policy: TabSuspensionPolicy(memoryMode: .balanced)
        )
        tabSuspensionRuntime.refreshLazyRestoreQueue(lazyRestoreContext)
        XCTAssertEqual(refreshedLazyRestoreContexts, [lazyRestoreContext])

        let backgroundMediaRuntime = try XCTUnwrap(attachedBackgroundMediaRuntime)
        XCTAssertIdentical(backgroundMediaRuntime.webViewCoordinator(), coordinator)
        XCTAssertTrue(backgroundMediaRuntime.energySaverActive())
        XCTAssertEqual(backgroundMediaRuntime.allKnownTabs().map(\.id), [tab.id])
        XCTAssertEqual(
            backgroundMediaRuntime.visibleTabIDsByWindow(),
            [visibleWindowID: [visibleTabID]]
        )

        let runtimeNotifications = BrowserTabRuntimeCompositionService.runtimeNotifications(
            dependencies: dependencies
        )
        runtimeNotifications.tabActivated(tab, previousTab)
        runtimeNotifications.tabSelectionChanged("tab-selection")

        XCTAssertEqual(activatedTabs.count, 1)
        XCTAssertEqual(activatedTabs[0].new, tab.id)
        XCTAssertEqual(activatedTabs[0].previous, previousTab.id)
        XCTAssertEqual(tabSuspensionReconcileReasons, ["tab-selection"])
        XCTAssertEqual(backgroundMediaReconcileReasons, ["tab-selection"])

        structuralChanges.send()
        await fulfillment(of: [structuralChangeHandled], timeout: 1)

        XCTAssertEqual(tabStructuralRevisionCount, 1)
        XCTAssertEqual(
            tabSuspensionReconcileReasons,
            ["tab-selection", "tab-structure-changed"]
        )
        XCTAssertEqual(
            backgroundMediaReconcileReasons,
            ["tab-selection", "tab-structure-changed"]
        )
    }

    func testDetachedRuntimeTabContextMenuForegroundOpenDoesNotUseActiveWindow() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Detached Runtime Source")
        let activeTab = browserManager.tabManager.createNewTab(
            url: "https://active.example",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentTabId = activeTab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let detachedTab = Tab(
            url: URL(string: "https://detached.example")!,
            loadsCachedFaviconOnInit: false
        )
        detachedTab.spaceId = space.id
        detachedTab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

        let targetURL = URL(string: "https://detached-target.example")!
        detachedTab.openContextMenuURLInForegroundTab(targetURL)

        XCTAssertFalse(
            browserManager.tabManager.allTabs().contains { $0.url == targetURL },
            "Detached tab runtime actions must not retarget through the active window."
        )
        XCTAssertEqual(windowState.currentTabId, activeTab.id)
    }

    func testTabSuspensionSelectedTabsDoNotUseGlobalCurrentTabFallback() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let selectedSpace = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Selected")
        let selectedTab = browserManager.tabManager.createNewTab(
            url: "https://selected.example",
            in: selectedSpace,
            activate: true
        )
        let staleSpace = browserManager.tabManager.createSpace(name: "Stale")
        let staleGlobalTab = browserManager.tabManager.createNewTab(
            url: "https://stale.example",
            in: staleSpace,
            activate: false
        )

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = selectedSpace.id
        windowState.currentTabId = selectedTab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)
        browserManager.tabManager.currentTab = staleGlobalTab

        let context = browserManager.tabSuspensionService.suspensionEvaluationContext(
            policy: TabSuspensionPolicy(memoryMode: .balanced)
        )

        XCTAssertEqual(context.selectedTabIDs, [selectedTab.id])
        XCTAssertFalse(context.selectedTabIDs.contains(staleGlobalTab.id))
    }

    private func compositorManagerCanUseAttachedRuntime(_ browserManager: BrowserManager) -> Bool {
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Compositor Runtime Wiring")
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/compositor",
            in: space,
            activate: true
        )
        tab.replaceUntrackedWebView(WKWebView())

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        browserManager.compositorManager.unloadTab(tab)
        return tab.currentWebView != nil
    }

    private func splitManagerCanUseAttachedRuntime(_ browserManager: BrowserManager) -> Bool {
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Runtime Wiring")
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        browserManager.splitManager.createEmptySplit(in: windowState)
        return browserManager.splitManager.splitGroup(for: windowState.id) != nil
    }

    private func tabManagerRuntimeCanPrepareCreatedTabs(_ browserManager: BrowserManager) -> Bool {
        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "TabManager Runtime Wiring")
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/tab-manager-runtime",
            in: space,
            activate: false
        )
        return tab.hasBrowserRuntime && tab.sumiSettings === browserManager.sumiSettings
    }

    private func downloadRetryRuntimeCanResolveWindowOwnedWebView(_ browserManager: BrowserManager) -> Bool {
        let windowRegistry = WindowRegistry()
        let coordinator = WebViewCoordinator()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = coordinator

        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Download Runtime Wiring")
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/download",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let webView = WKWebView()
        coordinator.setWebView(webView, for: tab.id, in: windowState.id)

        guard let activeWindow = browserManager.downloadManager.retryRuntime.activeWindow(),
              let currentTab = browserManager.downloadManager.retryRuntime.currentTab(activeWindow),
              let resolvedWebView = browserManager.downloadManager.retryRuntime
                .windowOwnedWebView(currentTab, activeWindow.id)
        else {
            return false
        }

        return activeWindow === windowState
            && currentTab === tab
            && resolvedWebView === webView
    }

    private func boostsModuleCanUseAttachedRuntime(_ browserManager: BrowserManager) -> Bool {
        let windowRegistry = WindowRegistry()
        let coordinator = WebViewCoordinator()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = coordinator

        let profileId = UUID()
        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Boost Runtime Wiring", profileId: profileId)
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/boost",
            in: space,
            activate: true
        )
        tab.profileId = profileId
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentProfileId = profileId
        windowState.currentSpaceId = space.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        coordinator.setWebView(WKWebView(), for: tab.id, in: windowState.id)

        let started = browserManager.boostsModule.startZapSelection(
            for: SumiBoost(profileId: profileId, host: "example.com"),
            tab: tab,
            windowState: windowState,
            isEphemeral: false,
            onSelector: { _ in /* No-op. */ },
            onFinish: { /* No-op. */ }
        )
        browserManager.boostsModule.stopZapSelection()
        return started
    }

    private func auxiliaryWindowManagerCanUseAttachedRuntime(_ browserManager: BrowserManager) -> Bool {
        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Auxiliary Runtime Wiring")
        let sourceTab = browserManager.tabManager.createNewTab(
            url: "https://example.com/source",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentTabId = sourceTab.id
        windowState.window = NSWindow(
            contentRect: NSRect(x: 120, y: 120, width: 900, height: 700),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        guard let webView = browserManager.auxiliaryWindowManager.presentWebPopup(
            configuration: WKWebViewConfiguration(),
            request: URLRequest(url: URL(string: "https://example.com/popup")!),
            windowFeatures: WKWindowFeatures(),
            openerTab: sourceTab,
            shouldActivateApp: false
        ) else {
            return false
        }
        let session = browserManager.auxiliaryWindowManager.session(for: webView)
        browserManager.auxiliaryWindowManager.teardown(for: webView, reason: .managerCloseAll)
        return session?.openerTab === sourceTab
            && session?.tab.isAuxiliaryMiniWindow == true
    }

    private func glanceRuntimeCanPreparePreviewTabs(_ browserManager: BrowserManager) -> Bool {
        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Glance Runtime Wiring")
        let sourceTab = browserManager.tabManager.createNewTab(
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

    func testBrowserManagerPermissionFacadesRouteThroughScopedBridgeRegistry() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
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
            startupPersistence: BrowserManagerStartupPersistence(container: container),
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

    func testWebViewCoordinatorWiringPreparesVisibleWebViewsThroughBrowserManager() async throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let windowRegistry = WindowRegistry()
        let coordinator = WebViewCoordinator()
        browserManager.windowRegistry = windowRegistry
        browserManager.webViewCoordinator = coordinator
        await browserManager.drainProtectionRuntimeTasksForTests()

        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Visible WebView Runtime")
        let tab = browserManager.tabManager.createNewTab(
            url: "https://example.com/visible-webview",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        XCTAssertTrue(browserManager.prepareVisibleWebViews(for: windowState))
        XCTAssertNotNil(coordinator.getWebView(for: tab.id, in: windowState.id))
    }

    func testShellRuntimeCoordinatorBindingTransfersOwnershipAndCleanupPreparer() throws {
        let cleanupService = makeBrowsingDataCleanupService()
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            browsingDataCleanupService: cleanupService,
            permissionSiteActivityStore: try makeSiteActivityStore()
        )
        let firstCoordinator = WebViewCoordinator()
        let secondCoordinator = WebViewCoordinator()

        browserManager.webViewCoordinator = firstCoordinator

        XCTAssertIdentical(browserManager.webViewCoordinator, firstCoordinator)
        XCTAssertIdentical(cleanupService.destructiveCleanupPreparer as AnyObject, firstCoordinator)

        browserManager.webViewCoordinator = secondCoordinator

        XCTAssertIdentical(browserManager.webViewCoordinator, secondCoordinator)
        XCTAssertIdentical(cleanupService.destructiveCleanupPreparer as AnyObject, secondCoordinator)

        browserManager.webViewCoordinator = nil

        XCTAssertNil(browserManager.webViewCoordinator)
        XCTAssertNil(cleanupService.destructiveCleanupPreparer)
    }

    func testShellRuntimeWindowRegistryBindingUpdatesDependentRuntimeManagers() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let windowRegistry = WindowRegistry()

        browserManager.windowRegistry = windowRegistry

        XCTAssertIdentical(browserManager.windowRegistry, windowRegistry)
        XCTAssertIdentical(browserManager.glanceManager.windowRegistry, windowRegistry)
        XCTAssertIdentical(browserManager.splitManager.windowRegistry, windowRegistry)
    }

    func testBrowserManagerRuntimeDataServicesUseInjectedBundle() async throws {
        let browsingDataCleanupService = makeBrowsingDataCleanupService()
        let automaticCleanupService = FakeBrowsingDataCleanupScheduler()
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
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        XCTAssertIdentical(tab.faviconService as AnyObject, faviconService)
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

        browserManager.automaticDataCleanupOwner.scheduleAutomaticBrowsingDataCleanup(
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
                automaticBrowsingDataCleanupService: FakeBrowsingDataCleanupScheduler(),
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
            browserContext: WebsiteViewContextFactory.historyPageBrowserContext(for: browserManager),
            windowState: nil
        )
        let bookmarksViewModel = SumiBookmarksPageViewModel(
            browserContext: WebsiteViewContextFactory.bookmarksPageBrowserContext(for: browserManager),
            windowState: nil
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
            loadsCachedFaviconOnInit: false
        )
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))

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
    private(set) var configuredContextCount = 0
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

    func configure(context _: SumiNativeNowPlayingRuntimeContext) {
        configuredContextCount += 1
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
private final class FakeBrowsingDataCleanupScheduler: BrowsingDataCleanupScheduling {
    struct Schedule: Equatable {
        let retentionPeriod: SumiBrowsingDataRetentionPeriod
        let profileIds: [UUID]
        let currentProfileId: UUID?
        let force: Bool
        let reason: String
        let delayNanoseconds: UInt64?
    }

    private(set) var schedules: [Schedule] = []

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
        // nil means the cleanup scope includes both regular and ephemeral profile credentials.
        // swiftlint:disable:next discouraged_optional_boolean
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
