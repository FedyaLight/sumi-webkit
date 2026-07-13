import Foundation
import SwiftData
import SumiWebRuntime

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
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        startupPersistence: BrowserManagerStartupPersistence = .production,
        windowSessionSnapshotStore: WindowSessionSnapshotStore = WindowSessionSnapshotStore(
            key: BrowserManager.lastWindowSessionKey
        ),
        browserConfiguration: BrowserConfiguration? = nil,
        adBlockingModule: SumiAdBlockingModule? = nil,
        protectionCoordinator: SumiProtectionCoordinator? = nil,
        adblockZapperStore: SumiAdblockZapperStore? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        boostsModule: SumiBoostsModule? = nil,
        browsingDataCleanupService: SumiBrowsingDataCleanupService? = nil,
        dataServices: BrowserManagerDataServices = .production,
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
        sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling = SidebarHostRecoveryCoordinator()
    ) {
        self.init(
            webViewSessions: WebViewSessionRepository(),
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
            sidebarHostRecoveryCoordinator: sidebarHostRecoveryCoordinator
        )
    }
}

@MainActor
extension TabManager {
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
