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
        windowRegistry: WindowRegistry,
        moduleRegistry: SumiModuleRegistry = .unavailable(),
        startupPersistence: BrowserManagerStartupPersistence = .production,
        windowSessionSnapshotStore: WindowSessionSnapshotStore? = nil,
        browserConfiguration: BrowserConfiguration? = nil,
        adBlockingModule: SumiAdBlockingModule? = nil,
        protectionCoordinator: SumiProtectionCoordinator? = nil,
        adblockZapperStore: SumiAdblockZapperStore? = nil,
        extensionsModule: SumiExtensionsModule? = nil,
        boostsModule: SumiBoostsModule? = nil,
        browsingDataCleanupService: SumiBrowsingDataCleanupService? = nil,
        dataServices: BrowserManagerDataServices,
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
        initialTabRuntimePorts: RuntimePortRegistry? = nil,
        automaticallyStartPersistedStateLoad: Bool = true,
        automaticallyPrepareRuntime: Bool = true,
        defersNoncriticalStartupWork: Bool = false
    ) {
        let startupTrace = StartupPerformanceTrace.browserManagerInitStarted()
        defer { StartupPerformanceTrace.browserManagerInitFinished(startupTrace) }
        let resolvedBrowserConfiguration = browserConfiguration
            ?? BrowserConfiguration(
                autoplayPolicyStore: startupPersistence.autoplayPolicyStore
            )
        let resolvedWindowSessionSnapshotStore =
            windowSessionSnapshotStore ?? WindowSessionSnapshotStore(
                database: startupPersistence.database,
                key: BrowserManager.lastWindowSessionKey
            )
        self.init(
            kernel: BrowserCompositionRoot.makeKernel(
                webViewSessions: webViewSessions,
                windowRegistry: windowRegistry,
                moduleRegistry: moduleRegistry,
                startupPersistence: startupPersistence,
                windowSessionSnapshotStore: resolvedWindowSessionSnapshotStore,
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
                sidebarHostRecoveryCoordinator: sidebarHostRecoveryCoordinator,
                initialTabRuntimePorts: initialTabRuntimePorts,
                automaticallyStartPersistedStateLoad:
                    automaticallyStartPersistedStateLoad,
                defersNoncriticalStartupWork: defersNoncriticalStartupWork
            )
        )
        if automaticallyPrepareRuntime {
            prepareRuntimeForStartupRecovery()
        }
    }
}
