//
//  BrowserManager+KernelInit.swift
//  Sumi
//
//  Public construction seam: CompositionRoot builds BrowserKernelGraph; this
//  convenience init forwards into the designated init(kernel:).
//

import Foundation
import SumiWebRuntime

extension BrowserManager {
    convenience init(
        webViewSessions: WebViewSessionRepository,
        moduleRegistry: SumiModuleRegistry = .shared,
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
        let startupTrace = StartupPerformanceTrace.browserManagerInitStarted()
        defer { StartupPerformanceTrace.browserManagerInitFinished(startupTrace) }
        let resolvedBrowserConfiguration = browserConfiguration
            ?? BrowserConfiguration(
                autoplayPolicyStore: startupPersistence.autoplayPolicyStore
            )
        self.init(
            kernel: BrowserCompositionRoot.makeKernel(
                webViewSessions: webViewSessions,
                moduleRegistry: moduleRegistry,
                startupPersistence: startupPersistence,
                windowSessionSnapshotStore: windowSessionSnapshotStore,
                browserConfiguration: resolvedBrowserConfiguration,
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
        )
    }
}
