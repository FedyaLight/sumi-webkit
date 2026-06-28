import Foundation
import SwiftData
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
        let cleanupService = SumiBrowsingDataCleanupService()
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

    func testRuntimeWiringSourceOwnsPhase2AttachmentOrder() throws {
        let source = try source(named: "Sumi/Managers/BrowserManager/BrowserManagerRuntimeWiring.swift")
        let orderedTokens = [
            "browserManager.compositorManager.browserManager = browserManager",
            "browserManager.tabSuspensionService.attach(browserManager: browserManager)",
            "browserManager.backgroundMediaOptimizationService.attach(browserManager: browserManager)",
            "browserManager.splitManager.browserManager = browserManager",
            "browserManager.splitManager.windowRegistry = browserManager.windowRegistry",
            "browserManager.tabManager.browserManager = browserManager",
            "browserManager.tabManager.attachRuntimeContext(",
            "BrowserManagerTabRuntimeContext(browserManager: browserManager)",
            "browserManager.tabManager.reattachBrowserManager(browserManager)",
            "browserManager.liveFolderManager.attach(browserManager: browserManager)",
            "browserManager.downloadManager.browserManager = browserManager",
            "browserManager.extensionsModule.attach(browserManager: browserManager)",
            "browserManager.userscriptsModule.attach(browserManager: browserManager)",
            "browserManager.boostsModule.attach(browserManager: browserManager)",
            "let structuralChangeCancellable = bindTabManagerStructuralUpdates(for: browserManager)",
            "browserManager.auxiliaryWindowManager.attach(browserManager: browserManager)",
            "browserManager.glanceManager.attach(browserManager: browserManager)",
            "browserManager.authenticationManager.attach(browserManager: browserManager)",
        ]

        try assertTokensAppearInOrder(orderedTokens, in: source)
    }

    func testRuntimeWiringSourceOwnsBrowserExtensionNotificationGlue() throws {
        let runtimeWiringSource = try source(named: "Sumi/Managers/BrowserManager/BrowserManagerRuntimeWiring.swift")
        let browserManagerSource = try source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")
        let webViewLifecycleSource = try source(
            named: "Sumi/Managers/BrowserManager/BrowserManager+WebViewLifecycle.swift"
        )

        for expectedToken in [
            "func tabSelectionRuntimeNotifications(",
            "browserManager.extensionsModule.notifyTabActivatedIfLoaded",
            "browserManager.extensionsModule.notifyWindowOpenedIfLoaded",
            "browserManager.extensionsModule.notifyWindowFocusedIfLoaded",
            "browserManager.extensionsModule.notifyTabClosedIfLoaded",
            "scheduleTabRuntimeReconcile(for: browserManager, reason: reason)",
        ] {
            XCTAssertTrue(runtimeWiringSource.contains(expectedToken), expectedToken)
        }

        for forbiddenToken in [
            "extensionsModule.notifyTabActivatedIfLoaded",
            "extensionsModule.notifyWindowOpenedIfLoaded",
            "extensionsModule.notifyWindowFocusedIfLoaded",
        ] {
            XCTAssertFalse(browserManagerSource.contains(forbiddenToken), forbiddenToken)
        }
        XCTAssertFalse(webViewLifecycleSource.contains("extensionsModule.notifyTabClosedIfLoaded"))
    }

    func testBrowserManagerInitDelegatesPhase2Wiring() throws {
        let source = try source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")

        XCTAssertTrue(
            source.contains("structuralChangeCancellable = BrowserManagerRuntimeWiring.attach(to: self)")
        )
        for forbiddenToken in [
            "self.tabSuspensionService.attach(browserManager: self)",
            "self.backgroundMediaOptimizationService.attach(browserManager: self)",
            "self.tabManager.reattachBrowserManager(self)",
            "self.liveFolderManager.attach(browserManager: self)",
            "self.extensionsModule.attach(browserManager: self)",
            "self.userscriptsModule.attach(browserManager: self)",
            "self.boostsModule.attach(browserManager: self)",
            "self.auxiliaryWindowManager.attach(browserManager: self)",
            "self.glanceManager.attach(browserManager: self)",
            "self.authenticationManager.attach(browserManager: self)",
        ] {
            XCTAssertFalse(source.contains(forbiddenToken), forbiddenToken)
        }
    }

    func testBrowserManagerDelegatesWindowSessionActivationFacadeToOwner() throws {
        let browserManagerSource = try source(named: "Sumi/Managers/BrowserManager/BrowserManager.swift")
        let ownerSource = try source(named: "Sumi/Managers/BrowserManager/BrowserWindowSessionActivationOwner.swift")
        let expectedBrowserManagerTokens = [
            "private lazy var windowSessionActivationOwner = BrowserWindowSessionActivationOwner(",
            "func setupWindowState(_ windowState: BrowserWindowState) {\n        windowSessionActivationOwner.setupWindowState(windowState)\n    }",
            "func setActiveWindowState(_ windowState: BrowserWindowState) {",
            "windowSessionActivationOwner.setActiveWindowState(windowState)",
            "func persistWindowSession(for windowState: BrowserWindowState) {\n        windowSessionActivationOwner.persistWindowSession(for: windowState)\n    }",
            "windowSessionActivationOwner.flushPendingWindowSessionPersistence()",
            "scheduleNativeNowPlayingRefresh: { delayNanoseconds in",
        ]

        XCTAssertFalse(
            browserManagerSource.contains("final class BrowserWindowSessionActivationOwner")
        )
        for expectedToken in expectedBrowserManagerTokens {
            XCTAssertTrue(browserManagerSource.contains(expectedToken), expectedToken)
        }
        for expectedOwnerToken in [
            "final class BrowserWindowSessionActivationOwner",
            "let scheduleNativeNowPlayingRefresh: @MainActor (UInt64) -> Void",
            "dependencies.scheduleNativeNowPlayingRefresh(0)",
            "dependencies.windowSessionService.persistWindowSession(",
        ] {
            XCTAssertTrue(ownerSource.contains(expectedOwnerToken), expectedOwnerToken)
        }
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

    private func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private func assertTokensAppearInOrder(
        _ tokens: [String],
        in source: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        var searchStart = source.startIndex
        for token in tokens {
            let range = try XCTUnwrap(
                source.range(of: token, range: searchStart..<source.endIndex),
                "Missing or out-of-order token: \(token)",
                file: file,
                line: line
            )
            searchStart = range.upperBound
        }
    }
}
