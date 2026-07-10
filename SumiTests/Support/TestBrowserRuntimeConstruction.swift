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
    func bindTestWebViewCoordinator(
        _ candidate: WebViewCoordinator? = nil
    ) -> WebViewCoordinator {
        if let current = webViewCoordinator {
            precondition(
                candidate == nil || current === candidate,
                "A test browser session cannot replace its WebViewCoordinator"
            )
            return current
        }

        let coordinator = candidate
            ?? WebViewCoordinator(webViewSessions: webViewSessions)
        webViewCoordinator = coordinator
        return coordinator
    }

    convenience init(
        moduleRegistry: SumiModuleRegistry = .shared,
        startupPersistence: BrowserManagerStartupPersistence = .production,
        browserConfiguration: BrowserConfiguration? = nil,
        adBlockingModule: SumiAdBlockingModule? = nil,
        protectionCoordinator: SumiProtectionCoordinator? = nil,
        adblockZapperStore: SumiAdblockZapperStore? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        userscriptsModule: SumiUserscriptsModule? = nil,
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
            browserConfiguration: browserConfiguration,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator,
            adblockZapperStore: adblockZapperStore,
            extensionsModule: extensionsModule,
            userscriptsModule: userscriptsModule,
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

@MainActor
extension WebViewCoordinator {
    convenience init() {
        self.init(webViewSessions: WebViewSessionRepository())
    }
}
