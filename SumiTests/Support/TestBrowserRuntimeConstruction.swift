import Foundation
import SumiWebRuntime
import SwiftData

@testable import Sumi

/// Test-only isolated graph construction. Production code must receive the
/// process repository from `SumiApp`; tests that compose multiple runtime
/// owners pass one repository explicitly instead of using these conveniences.
@MainActor
extension BrowserManager {
    @discardableResult
    func testWebViewRuntime() -> WebViewRuntimeGraph {
        precondition(
            webViewRuntime.webViewSessions === webViewSessions,
            "A test browser session must use its canonical WebView runtime graph"
        )
        return webViewRuntime
    }

    convenience init(
        windowRegistry: WindowRegistry = WindowRegistry(),
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        startupPersistence: BrowserManagerStartupPersistence? = nil,
        windowSessionSnapshotStore: WindowSessionSnapshotStore? = nil,
        browserConfiguration: BrowserConfiguration? = nil,
        adBlockingModule: SumiAdBlockingModule? = nil,
        protectionCoordinator: SumiProtectionCoordinator? = nil,
        adblockZapperStore: SumiAdblockZapperStore? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        boostsModule: SumiBoostsModule? = nil,
        browsingDataCleanupService: SumiBrowsingDataCleanupService? = nil,
        dataServices: BrowserManagerDataServices = .unavailable(),
        nowPlayingController: any SumiNativeNowPlayingRuntimeControlling = SumiNativeNowPlayingController(),
        systemPermissionService: (any SumiSystemPermissionService)? = nil,
        permissionCoordinator: (any SumiPermissionCoordinating)? = nil,
        geolocationProvider: (any SumiGeolocationProviding)? = nil,
        notificationService: (any SumiNotificationServicing)? = nil,
        runtimePermissionController: (any SumiRuntimePermissionControlling)? = nil,
        filePickerPanelPresenter: (any SumiFilePickerPanelPresenting)? = nil,
        permissionIndicatorEventStore: SumiPermissionIndicatorEventStore? = nil,
        permissionRecentActivityStore: SumiPermissionRecentActivityStore? = nil,
        permissionSiteActivityStore: SumiPermissionSiteActivityStore? = nil,
        permissionCleanupService: SumiPermissionCleanupService? = nil,
        blockedPopupStore: SumiBlockedPopupStore? = nil,
        externalAppResolver: any SumiExternalAppResolving = SumiNSWorkspaceExternalAppResolver(),
        externalSchemeSessionStore: SumiExternalSchemeSessionStore? = nil,
        permissionBridgeOverrides: BrowserPermissionBridgeRegistry.Overrides = .init(),
        sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator(),
        runtimePorts: RuntimePortRegistry? = nil,
        automaticallyStartPersistedStateLoad: Bool = true
    ) {
        let startupPersistence = startupPersistence
            ?? Self.makeIsolatedTestStartupPersistence()
        let windowSessionSnapshotStore = windowSessionSnapshotStore
            ?? Self.makeIsolatedTestWindowSessionSnapshotStore()
        self.init(
            webViewSessions: WebViewSessionRepository(),
            windowRegistry: windowRegistry,
            moduleRegistry: moduleRegistry,
            startupPersistence: startupPersistence,
            windowSessionSnapshotStore: windowSessionSnapshotStore,
            browserConfiguration: browserConfiguration,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator,
            adblockZapperStore: adblockZapperStore,
            extensionsModule: extensionsModule,
            boostsModule: boostsModule,
            browsingDataCleanupService: browsingDataCleanupService,
            dataServices: dataServices,
            nowPlayingController: nowPlayingController,
            systemPermissionService: systemPermissionService,
            permissionCoordinator: permissionCoordinator,
            geolocationProvider: geolocationProvider,
            notificationService: notificationService,
            runtimePermissionController: runtimePermissionController,
            filePickerPanelPresenter: filePickerPanelPresenter,
            permissionIndicatorEventStore: permissionIndicatorEventStore,
            permissionRecentActivityStore: permissionRecentActivityStore,
            permissionSiteActivityStore: permissionSiteActivityStore,
            permissionCleanupService: permissionCleanupService,
            blockedPopupStore: blockedPopupStore,
            externalAppResolver: externalAppResolver,
            externalSchemeSessionStore: externalSchemeSessionStore,
            permissionBridgeOverrides: permissionBridgeOverrides,
            sidebarHostRecoveryCoordinator: sidebarHostRecoveryCoordinator,
            initialTabRuntimePorts: runtimePorts,
            automaticallyStartPersistedStateLoad:
                automaticallyStartPersistedStateLoad
        )
    }

    private static func makeIsolatedTestStartupPersistence()
        -> BrowserManagerStartupPersistence {
        do {
            return BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupModelContainer()
            )
        } catch {
            preconditionFailure(
                "Could not construct isolated BrowserManager test persistence: \(error)"
            )
        }
    }

    private static func makeIsolatedTestWindowSessionSnapshotStore()
        -> WindowSessionSnapshotStore {
        let userDefaults = TestOwnedWindowSessionUserDefaults()
        return WindowSessionSnapshotStore(
            key: "SumiTests.window-session.\(UUID().uuidString)",
            userDefaults: userDefaults,
            environment: { [:] }
        )
    }
}

final class TestOwnedWindowSessionUserDefaults: UserDefaults {
    let ownedSuiteName: String

    init() {
        ownedSuiteName = "SumiTests.window-session.\(UUID().uuidString)"
        super.init(suiteName: ownedSuiteName)!
    }

    deinit {
        removePersistentDomain(forName: ownedSuiteName)
    }
}

@MainActor
extension TabManager {
    convenience init(
        runtimePorts: RuntimePortRegistry? = nil,
        context: ModelContext,
        webViewSessions: WebViewSessionRepository,
        loadPersistedState: Bool = true,
        automaticallyStartPersistedStateLoad: Bool = true,
        tabStructureEventBus: TabStructureEventBus? = nil,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        faviconCapabilities: BrowserFaviconCapabilities = TabDependencyIsolationDefaults.faviconCapabilities,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore
    ) {
        self.init(
            context: context,
            webViewSessions: webViewSessions,
            profileReferenceAdmission: .testingAllowingReferences(),
            loadPersistedState: loadPersistedState,
            automaticallyStartPersistedStateLoad: automaticallyStartPersistedStateLoad,
            tabStructureEventBus: tabStructureEventBus,
            faviconService: faviconService,
            faviconCapabilities: faviconCapabilities,
            visitedLinkStore: visitedLinkStore
        )
        if let runtimePorts {
            runtimePortConnection.attach(runtimePorts)
        }
    }

    convenience init(
        runtimePorts: RuntimePortRegistry? = nil,
        context: ModelContext,
        loadPersistedState: Bool = true,
        automaticallyStartPersistedStateLoad: Bool = true,
        tabStructureEventBus: TabStructureEventBus? = nil,
        faviconService: any BrowserFaviconServicing = TabDependencyIsolationDefaults.faviconService,
        faviconCapabilities: BrowserFaviconCapabilities = TabDependencyIsolationDefaults.faviconCapabilities,
        visitedLinkStore: any BrowserVisitedLinkStoreManaging = TabDependencyIsolationDefaults.visitedLinkStore
    ) {
        self.init(
            runtimePorts: runtimePorts,
            context: context,
            webViewSessions: WebViewSessionRepository(),
            loadPersistedState: loadPersistedState,
            automaticallyStartPersistedStateLoad: automaticallyStartPersistedStateLoad,
            tabStructureEventBus: tabStructureEventBus,
            faviconService: faviconService,
            faviconCapabilities: faviconCapabilities,
            visitedLinkStore: visitedLinkStore
        )
    }
}
