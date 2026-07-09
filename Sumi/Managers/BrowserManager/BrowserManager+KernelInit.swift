//
//  BrowserManager+KernelInit.swift
//  Sumi
//
//  Public construction seam: CompositionRoot builds BrowserKernelGraph; this
//  convenience init forwards into the designated init(kernel:).
//

import Foundation
import SumiBrowserCore

extension BrowserManager {
    convenience init(
        moduleRegistry: SumiModuleRegistry = .shared,
        startupPersistence: BrowserManagerStartupPersistence = .production,
        browserConfiguration: BrowserConfiguration = .shared,
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
        let startupTrace = StartupPerformanceTrace.browserManagerInitStarted()
        defer { StartupPerformanceTrace.browserManagerInitFinished(startupTrace) }
        self.init(
            kernel: BrowserCompositionRoot.makeKernel(
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
        )
    }
}
