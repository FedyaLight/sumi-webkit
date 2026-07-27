import AppKit
import Foundation
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
        database: SumiDatabase,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        adBlockingModule: SumiAdBlockingModule? = nil,
        protectionCoordinator: SumiProtectionCoordinator? = nil,
        adblockZapperStore: SumiAdblockZapperStore? = nil,
        boostsModule: SumiBoostsModule? = nil
    ) -> AssembledModules {
        let resolvedAdBlocking = adBlockingModule
            ?? SumiAdBlockingModule(
                moduleRegistry: moduleRegistry,
                database: database,
                compiledRuleListCatalog: compiledRuleListCatalog
            )
        let resolvedProtection = protectionCoordinator
            ?? SumiProtectionCoordinator(
                settings: SumiProtectionSettings(userDefaults: moduleRegistry.userDefaults),
                adBlockingModule: resolvedAdBlocking,
                bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore(
                    userDefaults: moduleRegistry.userDefaults
                ),
                compiledRuleListCatalog: compiledRuleListCatalog
            )
        return AssembledModules(
            adBlockingModule: resolvedAdBlocking,
            protectionCoordinator: resolvedProtection,
            adblockZapperStore: adblockZapperStore
                ?? SumiAdblockZapperStore(
                    database: database,
                    profileReferenceAdmission: profileReferenceAdmission
                ),
            boostsModule: boostsModule ?? SumiBoostsModule(
                moduleRegistry: moduleRegistry,
                storeFactory: {
                    SumiBoostStore(
                        profileReferenceAdmission: profileReferenceAdmission
                    )
                }
            )
        )
    }

    static func makeExtensionsModule(
        moduleRegistry: SumiModuleRegistry,
        database: SumiDatabase,
        browserConfiguration: BrowserConfiguration,
        initialProfileProvider: @escaping @MainActor () -> Profile?,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger,
        compiledRuleListCatalog: SumiCompiledContentRuleListCataloging,
        extensionsModule: SumiExtensionsModule? = nil
    ) -> SumiExtensionsModule {
        extensionsModule
            ?? SumiExtensionsModule(
                moduleRegistry: moduleRegistry,
                database: database,
                browserConfiguration: browserConfiguration,
                initialProfileProvider: initialProfileProvider,
                profileReferenceAdmission: profileReferenceAdmission,
                compiledRuleListCatalog: compiledRuleListCatalog
            )
    }

    static func makeBookmarkManager(
        database: SumiDatabase,
        faviconService: any BrowserFaviconServicing,
        initialProfile: Profile?
    ) -> SumiBookmarkManager {
        let bookmarkManager = SumiBookmarkManager(
            database: database,
            faviconService: faviconService
        )
        if let initialProfile {
            bookmarkManager.setFaviconPrefetchPartition(
                faviconService.partition(profile: initialProfile)
            )
        }
        return bookmarkManager
    }

    static func makeProfileManager(
        database: SumiDatabase,
        dataServices: BrowserManagerDataServices,
        profileReferenceAdmission: ProfileReferenceAdmissionLedger
    ) -> ProfileManager {
        ProfileManager(
            database: database,
            profileReferenceAdmission: profileReferenceAdmission,
            faviconService: dataServices.faviconService,
            visitedLinkStore: dataServices.visitedLinkStore
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
        database: SumiDatabase,
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
                        database: database
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
        windowRegistry: WindowRegistry,
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
        sidebarHostRecoveryCoordinator: SidebarHostRecoveryHandling,
        initialTabRuntimePorts: RuntimePortRegistry?,
        automaticallyStartPersistedStateLoad: Bool
    ) -> BrowserKernelGraph {
        let resolvedDataServices = browsingDataCleanupService.map {
            dataServices.replacing(browsingDataCleanupService: $0)
        } ?? dataServices
        let startupDatabase = startupPersistence.database
        let windowSessionPersistence = WindowSessionPersistenceRuntime(
            snapshotStore: windowSessionSnapshotStore
        )
        let profileReferenceAdmission: ProfileReferenceAdmissionLedger
        let profileRetirementStartupPreflight: ProfileRetirementStartupPreflightStatus
        do {
            let admission = try ProfileReferenceAdmissionLedger(
                database: startupDatabase
            )
            try ProfileRetirementStartupRecovery.cancelReservedReservations(
                in: admission
            )
            profileReferenceAdmission = admission
            profileRetirementStartupPreflight = .ready
        } catch {
            RuntimeDiagnostics.emit(
                "[ProfileRetirement] Startup preflight failed: \(error)"
            )
            profileReferenceAdmission = .failClosed()
            profileRetirementStartupPreflight = .failed(
                message: "Sumi could not safely prepare pending profile deletion recovery. \(error.localizedDescription)"
            )
        }
        let liveFoldersModule = SumiLiveFoldersModule(
            moduleRegistry: moduleRegistry
        )
        let tabStructureEventBus = TabStructureEventBus()
        let compiledRuleListCatalog =
            SumiCompiledContentRuleListCatalog(database: startupDatabase)
        let modules = assembleModules(
            moduleRegistry: moduleRegistry,
            database: startupDatabase,
            profileReferenceAdmission: profileReferenceAdmission,
            compiledRuleListCatalog: compiledRuleListCatalog,
            adBlockingModule: adBlockingModule,
            protectionCoordinator: protectionCoordinator,
            adblockZapperStore: adblockZapperStore,
            boostsModule: boostsModule
        )
        let profileManager = makeProfileManager(
            database: startupDatabase,
            dataServices: resolvedDataServices,
            profileReferenceAdmission: profileReferenceAdmission
        )
        profileManager.ensureDefaultProfile()
        let initialProfile = profileManager.profiles.first
        let lastSessionWindowsStore = LastSessionWindowsStore(
            database: startupDatabase
        )
        let downloadFileManager = FileManager.default
        let downloadOrphanCleaner = SumiDownloadOrphanCleaner(
            fileManager: downloadFileManager
        )
        let downloadFlyAnimationCenter = DownloadFlyAnimationCenter()
        let downloadTransactionFactory = DownloadTransactionFactory(
            destinations: SumiDownloadDestinationAllocator(
                fileManager: downloadFileManager,
                orphanCleaner: downloadOrphanCleaner
            ),
            finalizer: SumiDownloadFileFinalizer(
                fileManager: downloadFileManager
            ),
            progressPublisher: SumiDownloadProgressPublisher(
                flyAnimationCenter: downloadFlyAnimationCenter,
                dockDestinationChecker: SystemDockDownloadDestinationChecker()
            )
        )
        let downloadManager = DownloadManager(
            coordinator: DownloadListCoordinator(
                transactionFactory: downloadTransactionFactory,
                promptPresenter: SumiDownloadPromptPresenter()
            ),
            workspace: SumiDownloadWorkspace(
                workspace: .shared,
                fileManager: downloadFileManager
            ),
            flyAnimationCenter: downloadFlyAnimationCenter
        )
        let resolvedExtensionsModule = makeExtensionsModule(
            moduleRegistry: moduleRegistry,
            database: startupDatabase,
            browserConfiguration: browserConfiguration,
            initialProfileProvider: { initialProfile },
            profileReferenceAdmission: profileReferenceAdmission,
            compiledRuleListCatalog: compiledRuleListCatalog,
            extensionsModule: extensionsModule
        )
        return makeKernelWithTabSession(
            database: startupDatabase,
            windowRegistry: windowRegistry,
            moduleRegistry: moduleRegistry,
            sidebarHostRecoveryCoordinator: sidebarHostRecoveryCoordinator,
            adBlockingModule: modules.adBlockingModule,
            protectionCoordinator: modules.protectionCoordinator,
            adblockZapperStore: modules.adblockZapperStore,
            windowSessionPersistence: windowSessionPersistence,
            profileRetirementStartupPreflight: profileRetirementStartupPreflight,
            profileManager: profileManager,
            optionalModules: OptionalModuleHost(
                extensionsModule: resolvedExtensionsModule,
                boostsModule: modules.boostsModule,
                liveFoldersModule: liveFoldersModule
            ),
            tabStructureEventBus: tabStructureEventBus,
            webViewSessions: webViewSessions,
            dataServices: resolvedDataServices,
            initialProfile: initialProfile,
            profileReferenceAdmission: profileReferenceAdmission,
            downloadManager: downloadManager,
            downloadTransportFactory: SumiWebKitDownloadTransportFactory(),
            authenticationManager: AuthenticationManager(),
            historyManager: HistoryManager(
                database: startupDatabase,
                profileId: initialProfile?.id,
                faviconCleaner: resolvedDataServices.historyFaviconCleaner,
                visitedLinkStore: resolvedDataServices.historyVisitedLinkStore
            ),
            bookmarkManager: makeBookmarkManager(
                database: startupDatabase,
                faviconService: resolvedDataServices.faviconService,
                initialProfile: initialProfile
            ),
            recentlyClosedManager: RecentlyClosedManager(
                profileReferenceAdmission: profileReferenceAdmission
            ),
            lastSessionWindowsStore: lastSessionWindowsStore,
            startupSessionRestoreOwner: BrowserStartupSessionRestoreOwner(
                lastSessionWindowsStore: lastSessionWindowsStore
            ),
            compositorManager: TabCompositorManager(),
            tabSuspensionController: TabSuspensionController(
                memoryMonitor: SumiMemoryPressureMonitor()
            ),
            workspaceThemeCoordinator: WorkspaceThemeCoordinator(),
            findManager: FindManager(),
            browserConfiguration: browserConfiguration,
            browsingDataCleanupService: resolvedDataServices.browsingDataCleanupService,
            nativeNowPlayingController: nowPlayingController,
            permissionRuntime: makePermissionRuntime(
                makePermissionRuntimeBootstrap(
                    database: startupDatabase,
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
            ),
            initialTabRuntimePorts: initialTabRuntimePorts,
            loadPersistedState: true,
            automaticallyStartPersistedStateLoad:
                automaticallyStartPersistedStateLoad
        )
    }
}
