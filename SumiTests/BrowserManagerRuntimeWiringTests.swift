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

        XCTAssertTrue(browserManager.compositorManager.browserManager === browserManager)
        XCTAssertTrue(browserManager.tabManager.browserManager === browserManager)
        XCTAssertTrue(browserManager.tabManager.runtimeContext is BrowserManagerTabRuntimeContext)
        XCTAssertTrue(browserManager.splitManager.browserManager === browserManager)
        XCTAssertTrue(browserManager.downloadManager.browserManager === browserManager)
        XCTAssertTrue(browserManager.extensionsModule.browserManager === browserManager)
        XCTAssertTrue(browserManager.userscriptsModule.browserManager === browserManager)
        XCTAssertTrue(browserManager.boostsModule.browserManager === browserManager)
        XCTAssertTrue(browserManager.auxiliaryWindowManager.browserManager === browserManager)
        XCTAssertTrue(browserManager.glanceManager.browserManager === browserManager)
        XCTAssertFalse(browserManager.extensionsModule.hasLoadedRuntime)
        XCTAssertFalse(browserManager.userscriptsModule.hasLoadedRuntime)
    }

    func testBrowserManagerInitializationRetainsInjectedPermissionRuntimeDependencies() throws {
        let container = try makeInMemoryStartupContainer()
        let permissionStore = SwiftDataPermissionStore(container: container)
        let recentActivityStore = SumiPermissionRecentActivityStore()
        let siteActivityStore = SumiPermissionSiteActivityStore(
            userDefaults: try XCTUnwrap(
                UserDefaults(suiteName: "BrowserManagerRuntimeWiringTests-\(UUID().uuidString)")
            )
        )
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

        XCTAssertTrue(browserManager.permissionIndicatorEventStore === indicatorEventStore)
        XCTAssertTrue(browserManager.permissionRecentActivityStore === recentActivityStore)
        XCTAssertTrue(browserManager.permissionSiteActivityStore === siteActivityStore)
        XCTAssertTrue(browserManager.permissionCleanupService === cleanupService)
        XCTAssertTrue(browserManager.blockedPopupStore === blockedPopupStore)
        XCTAssertTrue(browserManager.externalSchemeSessionStore === externalSchemeSessionStore)
    }

    func testRuntimeNotificationsPreserveLazyExtensionRuntime() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
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
            "browserManager.authenticationManager.attach(browserManager: browserManager)"
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
            "scheduleTabRuntimeReconcile(for: browserManager, reason: reason)"
        ] {
            XCTAssertTrue(runtimeWiringSource.contains(expectedToken), expectedToken)
        }

        for forbiddenToken in [
            "extensionsModule.notifyTabActivatedIfLoaded",
            "extensionsModule.notifyWindowOpenedIfLoaded",
            "extensionsModule.notifyWindowFocusedIfLoaded"
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
            "self.authenticationManager.attach(browserManager: self)"
        ] {
            XCTAssertFalse(source.contains(forbiddenToken), forbiddenToken)
        }
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
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
