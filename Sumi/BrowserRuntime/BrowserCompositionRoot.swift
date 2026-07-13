import Foundation
import SwiftData
import SumiWebRuntime

/// Composition root for browser kernel assembly (architecture plan A1).
/// Owns construction of always-on managers and optional module shells so
/// `BrowserManager` can shrink toward a thin session façade.
@MainActor
enum BrowserCompositionRoot {
    struct AssembledModules {
        let adBlockingModule: SumiAdBlockingModule
        let protectionCoordinator: SumiProtectionCoordinator
        let adblockZapperStore: SumiAdblockZapperStore
        let boostsModule: SumiBoostsModule
    }

    struct PermissionRuntimeBootstrap {
        let browserConfiguration: BrowserConfiguration
        let systemPermissionService: (any SumiSystemPermissionService)?
        let permissionCoordinator: (any SumiPermissionCoordinating)?
        let geolocationProvider: (any SumiGeolocationProviding)?
        let notificationService: (any SumiNotificationServicing)?
        let runtimePermissionController: (any SumiRuntimePermissionControlling)?
        let filePickerPanelPresenter: (any SumiFilePickerPanelPresenting)?
        let permissionIndicatorEventStore: SumiPermissionIndicatorEventStore?
        let permissionRecentActivityStore: SumiPermissionRecentActivityStore?
        let permissionSiteActivityStore: SumiPermissionSiteActivityStore
        let permissionCleanupService: SumiPermissionCleanupService?
        let blockedPopupStore: SumiBlockedPopupStore?
        let externalAppResolver: any SumiExternalAppResolving
        let externalSchemeSessionStore: SumiExternalSchemeSessionStore?
        let permissionBridgeOverrides: BrowserPermissionBridgeRegistry.Overrides
    }

    /// Assembles optional-module shells used at BrowserManager construction
    /// (except extensions, which need an initial profile snapshot).
    static func assembleModules(
        moduleRegistry: SumiModuleRegistry,
        modelContext: ModelContext,
        adBlockingModule: SumiAdBlockingModule? = nil,
        protectionCoordinator: SumiProtectionCoordinator? = nil,
        adblockZapperStore: SumiAdblockZapperStore? = nil,
        boostsModule: SumiBoostsModule? = nil
    ) -> AssembledModules {
        let resolvedAdBlocking = adBlockingModule
            ?? SumiAdBlockingModule(moduleRegistry: moduleRegistry)
        let resolvedProtection = protectionCoordinator
            ?? SumiProtectionCoordinator(
                settings: SumiProtectionSettings(userDefaults: moduleRegistry.userDefaults),
                adBlockingModule: resolvedAdBlocking,
                bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore(
                    userDefaults: moduleRegistry.userDefaults
                )
            )
        return AssembledModules(
            adBlockingModule: resolvedAdBlocking,
            protectionCoordinator: resolvedProtection,
            adblockZapperStore: adblockZapperStore
                ?? SumiAdblockZapperStore(userDefaults: moduleRegistry.userDefaults),
            boostsModule: boostsModule ?? SumiBoostsModule(
                moduleRegistry: moduleRegistry,
                storeFactory: { SumiBoostStore() }
            )
        )
    }

    static func makeExtensionsModule(
        moduleRegistry: SumiModuleRegistry,
        modelContext: ModelContext,
        browserConfiguration: BrowserConfiguration,
        initialProfileProvider: @escaping @MainActor () -> Profile?,
        extensionsModule: SumiExtensionsModule? = nil
    ) -> SumiExtensionsModule {
        extensionsModule
            ?? SumiExtensionsModule(
                moduleRegistry: moduleRegistry,
                context: modelContext,
                browserConfiguration: browserConfiguration,
                initialProfileProvider: initialProfileProvider
            )
    }

    static func makeBookmarkManager(
        faviconService: any BrowserFaviconServicing,
        initialProfile: Profile?
    ) -> SumiBookmarkManager {
        let bookmarkManager = SumiBookmarkManager(faviconService: faviconService)
        if let initialProfile {
            bookmarkManager.setFaviconPrefetchPartition(
                faviconService.partition(profile: initialProfile)
            )
        }
        return bookmarkManager
    }

    /// Always-on session managers constructed after the initial profile is known.
    struct AssembledSessionManagers {
        let tabManager: TabManager
        let downloadManager: DownloadManager
        let authenticationManager: AuthenticationManager
        let historyManager: HistoryManager
        let bookmarkManager: SumiBookmarkManager
        let recentlyClosedManager: RecentlyClosedManager
        let lastSessionWindowsStore: LastSessionWindowsStore
        let startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner
        let compositorManager: TabCompositorManager
        let tabSuspensionController: TabSuspensionController
        let workspaceThemeCoordinator: WorkspaceThemeCoordinator
        let findManager: FindManager
    }

    static func makeProfileManager(
        modelContext: ModelContext,
        dataServices: BrowserManagerDataServices
    ) -> ProfileManager {
        ProfileManager(
            context: modelContext,
            faviconService: dataServices.faviconService,
            visitedLinkStore: dataServices.visitedLinkStore
        )
    }

    static func makeSessionManagers(
        modelContext: ModelContext,
        tabStructureEventBus: TabStructureEventBus,
        webViewSessions: WebViewSessionRepository,
        dataServices: BrowserManagerDataServices,
        initialProfile: Profile?
    ) -> AssembledSessionManagers {
        let lastSessionWindowsStore = LastSessionWindowsStore()
        return AssembledSessionManagers(
            tabManager: TabManager(
                context: modelContext,
                webViewSessions: webViewSessions,
                automaticallyStartPersistedStateLoad: false,
                tabStructureEventBus: tabStructureEventBus,
                faviconService: dataServices.faviconService,
                faviconCapabilities: dataServices.faviconCapabilities,
                visitedLinkStore: dataServices.visitedLinkStore
            ),
            downloadManager: DownloadManager(),
            authenticationManager: AuthenticationManager(),
            historyManager: HistoryManager(
                context: modelContext,
                profileId: initialProfile?.id,
                faviconCleaner: dataServices.historyFaviconCleaner,
                visitedLinkStore: dataServices.historyVisitedLinkStore
            ),
            bookmarkManager: makeBookmarkManager(
                faviconService: dataServices.faviconService,
                initialProfile: initialProfile
            ),
            recentlyClosedManager: RecentlyClosedManager(),
            lastSessionWindowsStore: lastSessionWindowsStore,
            startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner(
                lastSessionWindowsStore: lastSessionWindowsStore
            ),
            compositorManager: TabCompositorManager(),
            tabSuspensionController: TabSuspensionController(
                memoryMonitor: SumiMemoryPressureMonitor()
            ),
            workspaceThemeCoordinator: WorkspaceThemeCoordinator(),
            findManager: FindManager()
        )
    }

    static func makePermissionRuntime(
        _ bootstrap: PermissionRuntimeBootstrap
    ) -> BrowserManagerPermissionRuntime {
        BrowserManagerPermissionRuntime(
            dependencies: BrowserManagerPermissionRuntime.Dependencies(
                browserConfiguration: bootstrap.browserConfiguration,
                systemPermissionService: bootstrap.systemPermissionService,
                permissionCoordinator: bootstrap.permissionCoordinator,
                geolocationProvider: bootstrap.geolocationProvider,
                notificationService: bootstrap.notificationService,
                runtimePermissionController: bootstrap.runtimePermissionController,
                filePickerPanelPresenter: bootstrap.filePickerPanelPresenter,
                permissionIndicatorEventStore: bootstrap.permissionIndicatorEventStore,
                permissionRecentActivityStore: bootstrap.permissionRecentActivityStore,
                permissionSiteActivityStore: bootstrap.permissionSiteActivityStore,
                permissionCleanupService: bootstrap.permissionCleanupService,
                blockedPopupStore: bootstrap.blockedPopupStore,
                externalAppResolver: bootstrap.externalAppResolver,
                externalSchemeSessionStore: bootstrap.externalSchemeSessionStore,
                permissionBridgeOverrides: bootstrap.permissionBridgeOverrides
            )
        )
    }

    static func makePermissionRuntimeBootstrap(
        browserConfiguration: BrowserConfiguration,
        systemPermissionService: (any SumiSystemPermissionService)?,
        permissionCoordinator: (any SumiPermissionCoordinating)?,
        geolocationProvider: (any SumiGeolocationProviding)?,
        notificationService: (any SumiNotificationServicing)?,
        runtimePermissionController: (any SumiRuntimePermissionControlling)?,
        filePickerPanelPresenter: (any SumiFilePickerPanelPresenting)?,
        permissionIndicatorEventStore: SumiPermissionIndicatorEventStore?,
        permissionRecentActivityStore: SumiPermissionRecentActivityStore?,
        permissionSiteActivityStore: SumiPermissionSiteActivityStore?,
        permissionCleanupService: SumiPermissionCleanupService?,
        blockedPopupStore: SumiBlockedPopupStore?,
        externalAppResolver: any SumiExternalAppResolving,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore?,
        permissionBridgeOverrides: BrowserPermissionBridgeRegistry.Overrides
    ) -> PermissionRuntimeBootstrap {
        PermissionRuntimeBootstrap(
            browserConfiguration: browserConfiguration,
            systemPermissionService: systemPermissionService,
            permissionCoordinator: permissionCoordinator,
            geolocationProvider: geolocationProvider,
            notificationService: notificationService,
            runtimePermissionController: runtimePermissionController,
            filePickerPanelPresenter: filePickerPanelPresenter,
            permissionIndicatorEventStore: permissionIndicatorEventStore,
            permissionRecentActivityStore: permissionRecentActivityStore,
            permissionSiteActivityStore: permissionSiteActivityStore
                ?? SumiPermissionSiteActivityStore(
                    persistenceAuthority: SumiPermissionPersistenceAuthority(
                        userDefaults: nil
                    )
                ),
            permissionCleanupService: permissionCleanupService,
            blockedPopupStore: blockedPopupStore,
            externalAppResolver: externalAppResolver,
            externalSchemeSessionStore: externalSchemeSessionStore,
            permissionBridgeOverrides: permissionBridgeOverrides
        )
    }

    /// Builds the always-on kernel graph so `BrowserManager` init only assigns fields.
    static func makeKernel(
        webViewSessions: WebViewSessionRepository,
        moduleRegistry: SumiModuleRegistry,
        startupPersistence: BrowserManagerStartupPersistence,
        windowSessionSnapshotStore: WindowSessionSnapshotStore,
        browserConfiguration: BrowserConfiguration,
        adBlockingModule: SumiAdBlockingModule?,
        protectionCoordinator: SumiProtectionCoordinator?,
        adblockZapperStore: SumiAdblockZapperStore?,
        extensionsModule: SumiExtensionsModule?,
        boostsModule: SumiBoostsModule?,
        browsingDataCleanupService: SumiBrowsingDataCleanupService?,
        dataServices: BrowserManagerDataServices,
        nowPlayingController: any SumiNativeNowPlayingRuntimeControlling,
        systemPermissionService: (any SumiSystemPermissionService)?,
        permissionCoordinator: (any SumiPermissionCoordinating)?,
        geolocationProvider: (any SumiGeolocationProviding)?,
        notificationService: (any SumiNotificationServicing)?,
        runtimePermissionController: (any SumiRuntimePermissionControlling)?,
        filePickerPanelPresenter: (any SumiFilePickerPanelPresenting)?,
        permissionIndicatorEventStore: SumiPermissionIndicatorEventStore?,
        permissionRecentActivityStore: SumiPermissionRecentActivityStore?,
        permissionSiteActivityStore: SumiPermissionSiteActivityStore?,
        permissionCleanupService: SumiPermissionCleanupService?,
        blockedPopupStore: SumiBlockedPopupStore?,
        externalAppResolver: any SumiExternalAppResolving,
        externalSchemeSessionStore: SumiExternalSchemeSessionStore?,
        permissionBridgeOverrides: BrowserPermissionBridgeRegistry.Overrides,
        sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling
    ) -> BrowserKernelGraph {
        let resolvedDataServices = browsingDataCleanupService.map {
            dataServices.replacing(browsingDataCleanupService: $0)
        } ?? dataServices
        let startupModelContext = startupPersistence.mainContext
        let windowSessionPersistence = WindowSessionPersistenceRuntime(
            snapshotStore: windowSessionSnapshotStore
        )
        let liveFoldersModule = SumiLiveFoldersModule(
            moduleRegistry: moduleRegistry
        )
        let tabStructureEventBus = TabStructureEventBus()
        let modules = assembleModules(
            moduleRegistry: moduleRegistry,
            modelContext: startupModelContext,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator,
            adblockZapperStore: adblockZapperStore,
            boostsModule: boostsModule
        )
        let profileManager = makeProfileManager(
            modelContext: startupModelContext,
            dataServices: resolvedDataServices
        )
        profileManager.ensureDefaultProfile()
        let initialProfile = profileManager.profiles.first
        let session = makeSessionManagers(
            modelContext: startupModelContext,
            tabStructureEventBus: tabStructureEventBus,
            webViewSessions: webViewSessions,
            dataServices: resolvedDataServices,
            initialProfile: initialProfile
        )
        let resolvedExtensionsModule = makeExtensionsModule(
            moduleRegistry: moduleRegistry,
            modelContext: startupModelContext,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { initialProfile },
            extensionsModule: extensionsModule
        )
        return BrowserKernelGraph(
            webViewSessions: webViewSessions,
            modelContext: startupModelContext,
            moduleRegistry: moduleRegistry,
            sidebarHostRecoveryCoordinator: sidebarHostRecoveryCoordinator,
            adBlockingModule: modules.adBlockingModule,
            protectionCoordinator: modules.protectionCoordinator,
            adblockZapperStore: modules.adblockZapperStore,
            startupWorkspaceTheme: StartupWorkspaceThemeResolver.resolve(
                windowSessionSnapshotStore: windowSessionSnapshotStore,
                modelContext: startupModelContext
            ),
            windowSessionPersistence: windowSessionPersistence,
            profileManager: profileManager,
            currentProfile: initialProfile,
            optionalModules: OptionalModuleHost(
                extensionsModule: resolvedExtensionsModule,
                boostsModule: modules.boostsModule,
                liveFoldersModule: liveFoldersModule
            ),
            tabManager: session.tabManager,
            downloadManager: session.downloadManager,
            authenticationManager: session.authenticationManager,
            historyManager: session.historyManager,
            bookmarkManager: session.bookmarkManager,
            recentlyClosedManager: session.recentlyClosedManager,
            lastSessionWindowsStore: session.lastSessionWindowsStore,
            startupSessionRestoreOwner: session.startupSessionRestoreOwner,
            compositorManager: session.compositorManager,
            tabSuspensionController: session.tabSuspensionController,
            workspaceThemeCoordinator: session.workspaceThemeCoordinator,
            findManager: session.findManager,
            browserConfiguration: browserConfiguration,
            dataServices: resolvedDataServices,
            browsingDataCleanupService: resolvedDataServices.browsingDataCleanupService,
            nativeNowPlayingController: nowPlayingController,
            permissionRuntime: makePermissionRuntime(
                makePermissionRuntimeBootstrap(
                    browserConfiguration: browserConfiguration,
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
                    permissionBridgeOverrides: permissionBridgeOverrides
                )
            )
        )
    }

}
