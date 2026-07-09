import Foundation
import SwiftData
import SumiBrowserCore

/// Composition root for browser kernel assembly (architecture plan A1).
/// Owns construction of always-on managers and optional module shells so
/// `BrowserManager` can shrink toward a thin session façade.
@MainActor
enum BrowserCompositionRoot {
    struct AssembledModules {
        let adBlockingModule: SumiAdBlockingModule
        let protectionCoordinator: SumiProtectionCoordinator
        let adblockZapperStore: SumiAdblockZapperStore
        let userscriptsModule: SumiUserscriptsModule
        let boostsModule: SumiBoostsModule
    }

    struct PermissionRuntimeBootstrap {
        let startupPersistence: BrowserManagerStartupPersistence
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
        userscriptsModule: SumiUserscriptsModule? = nil,
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
        SumiProtectionCoordinator.bindShared(resolvedProtection)

        return AssembledModules(
            adBlockingModule: resolvedAdBlocking,
            protectionCoordinator: resolvedProtection,
            adblockZapperStore: adblockZapperStore
                ?? SumiAdblockZapperStore(userDefaults: moduleRegistry.userDefaults),
            userscriptsModule: userscriptsModule
                ?? SumiUserscriptsModule(
                    moduleRegistry: moduleRegistry,
                    context: modelContext
                ),
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

    /// Shared tab-structure event bus for the process browser session.
    static func makeTabStructureEventBus() -> TabStructureEventBus {
        TabStructureEventBus()
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
        let tabSuspensionService: TabSuspensionService
        let splitManager: SplitViewManager
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
        dataServices: BrowserManagerDataServices,
        initialProfile: Profile?
    ) -> AssembledSessionManagers {
        let lastSessionWindowsStore = LastSessionWindowsStore()
        return AssembledSessionManagers(
            tabManager: TabManager(
                context: modelContext,
                tabStructureEventBus: tabStructureEventBus,
                faviconService: dataServices.faviconService,
                faviconImageService: dataServices.faviconImageService,
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
            tabSuspensionService: TabSuspensionService(
                memoryMonitor: SumiMemoryPressureMonitor()
            ),
            splitManager: SplitViewManager(),
            workspaceThemeCoordinator: WorkspaceThemeCoordinator(),
            findManager: FindManager()
        )
    }

    static func makePermissionRuntime(
        _ bootstrap: PermissionRuntimeBootstrap
    ) -> BrowserManagerPermissionRuntime {
        BrowserManagerPermissionRuntime(
            dependencies: BrowserManagerPermissionRuntime.Dependencies(
                startupPersistence: bootstrap.startupPersistence,
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
        startupPersistence: BrowserManagerStartupPersistence,
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
            startupPersistence: startupPersistence,
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
                ?? SumiPermissionSiteActivityStore(),
            permissionCleanupService: permissionCleanupService,
            blockedPopupStore: blockedPopupStore,
            externalAppResolver: externalAppResolver,
            externalSchemeSessionStore: externalSchemeSessionStore,
            permissionBridgeOverrides: permissionBridgeOverrides
        )
    }

    /// Builds the always-on kernel graph so `BrowserManager` init only assigns fields.
    static func makeKernel(
        moduleRegistry: SumiModuleRegistry,
        startupPersistence: BrowserManagerStartupPersistence,
        browserConfiguration: BrowserConfiguration,
        adBlockingModule: SumiAdBlockingModule?,
        protectionCoordinator: SumiProtectionCoordinator?,
        adblockZapperStore: SumiAdblockZapperStore?,
        extensionsModule: SumiExtensionsModule?,
        userscriptsModule: SumiUserscriptsModule?,
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
        let tabStructureEventBus = makeTabStructureEventBus()
        let modules = assembleModules(
            moduleRegistry: moduleRegistry,
            modelContext: startupModelContext,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator,
            adblockZapperStore: adblockZapperStore,
            userscriptsModule: userscriptsModule,
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
            dataServices: resolvedDataServices,
            initialProfile: initialProfile
        )
        return BrowserKernelGraph(
            modelContext: startupModelContext,
            moduleRegistry: moduleRegistry,
            liveFoldersModule: SumiLiveFoldersModule(moduleRegistry: moduleRegistry),
            sidebarHostRecoveryCoordinator: sidebarHostRecoveryCoordinator,
            tabStructureEventBus: tabStructureEventBus,
            adBlockingModule: modules.adBlockingModule,
            protectionCoordinator: modules.protectionCoordinator,
            adblockZapperStore: modules.adblockZapperStore,
            userscriptsModule: modules.userscriptsModule,
            boostsModule: modules.boostsModule,
            startupWorkspaceTheme: StartupWorkspaceThemeResolver.resolve(
                lastWindowSessionKey: BrowserManager.lastWindowSessionKey,
                modelContext: startupModelContext
            ),
            profileManager: profileManager,
            currentProfile: initialProfile,
            extensionsModule: makeExtensionsModule(
                moduleRegistry: moduleRegistry,
                modelContext: startupModelContext,
                browserConfiguration: browserConfiguration,
                initialProfileProvider: { initialProfile },
                extensionsModule: extensionsModule
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
            tabSuspensionService: session.tabSuspensionService,
            splitManager: session.splitManager,
            workspaceThemeCoordinator: session.workspaceThemeCoordinator,
            findManager: session.findManager,
            browserConfiguration: browserConfiguration,
            dataServices: resolvedDataServices,
            browsingDataCleanupService: resolvedDataServices.browsingDataCleanupService,
            nativeNowPlayingController: nowPlayingController,
            permissionRuntime: makePermissionRuntime(
                makePermissionRuntimeBootstrap(
                    startupPersistence: startupPersistence,
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

    /// Wires shell-runtime callbacks that need a live BrowserManager session.
    static func attachShellRuntime(to browserManager: BrowserManager) {
        browserManager.shellRuntime.attach(
            releaseWebViewCoordinator: { [weak browserManager] coordinator in
                guard browserManager != nil else { return }
                coordinator?.detachVisiblePreparationRuntimeContext()
                coordinator?.detachInitialDocumentRuntimeContext()
                coordinator?.detachShutdownRuntimeContext()
                coordinator?.detachBrowserRuntimeContext()
            },
            adoptWebViewCoordinator: { [weak browserManager] coordinator in
                guard let browserManager else { return }
                guard let coordinator else { return }
                coordinator.attachBrowserRuntimeContext(
                    BrowserWebViewRuntimeFactory.browserRuntimeContext(
                        for: browserManager
                    )
                )
                coordinator.attachInitialDocumentRuntimeContext(
                    BrowserWebViewRuntimeFactory.initialDocumentContext(
                        for: browserManager
                    )
                )
                coordinator.attachShutdownRuntimeContext(
                    BrowserWebViewRuntimeFactory.shutdownContext(
                        for: browserManager
                    )
                )
                coordinator.attachVisiblePreparationRuntimeContext(
                    BrowserWebViewRuntimeFactory.visiblePreparationContext(
                        for: browserManager
                    )
                )
            },
            setDestructiveCleanupPreparer: { [weak browserManager] coordinator in
                browserManager?.browsingDataCleanupService.destructiveCleanupPreparer = coordinator
            },
            windowRegistryChanged: { [weak browserManager] registry in
                guard let browserManager else { return }
                browserManager.glanceManager.windowRegistry = registry
                browserManager.splitManager.windowRegistry = registry
                Task { @MainActor [weak browserManager] in
                    await browserManager?.privacyBundle.permissionSidebarPinningOwner.reconcile(
                        reason: "window-registry-updated"
                    )
                }
                browserManager.backgroundMediaOptimizationService.scheduleReconcile(
                    reason: "window-registry-updated"
                )
                browserManager.reconcileStartupSessionIfPossible()
            }
        )
    }
}
