import SwiftData

@MainActor
final class BrowserManagerPermissionRuntime {
    struct Dependencies {
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

        init(
            startupPersistence: BrowserManagerStartupPersistence,
            browserConfiguration: BrowserConfiguration,
            systemPermissionService: (any SumiSystemPermissionService)? = nil,
            permissionCoordinator: (any SumiPermissionCoordinating)? = nil,
            geolocationProvider: (any SumiGeolocationProviding)? = nil,
            notificationService: (any SumiNotificationServicing)? = nil,
            runtimePermissionController: (any SumiRuntimePermissionControlling)? = nil,
            filePickerPanelPresenter: (any SumiFilePickerPanelPresenting)? = nil,
            permissionIndicatorEventStore: SumiPermissionIndicatorEventStore? = nil,
            permissionRecentActivityStore: SumiPermissionRecentActivityStore? = nil,
            permissionSiteActivityStore: SumiPermissionSiteActivityStore,
            permissionCleanupService: SumiPermissionCleanupService? = nil,
            blockedPopupStore: SumiBlockedPopupStore? = nil,
            externalAppResolver: any SumiExternalAppResolving,
            externalSchemeSessionStore: SumiExternalSchemeSessionStore? = nil,
            permissionBridgeOverrides: BrowserPermissionBridgeRegistry.Overrides = BrowserPermissionBridgeRegistry.Overrides()
        ) {
            self.startupPersistence = startupPersistence
            self.browserConfiguration = browserConfiguration
            self.systemPermissionService = systemPermissionService
            self.permissionCoordinator = permissionCoordinator
            self.geolocationProvider = geolocationProvider
            self.notificationService = notificationService
            self.runtimePermissionController = runtimePermissionController
            self.filePickerPanelPresenter = filePickerPanelPresenter
            self.permissionIndicatorEventStore = permissionIndicatorEventStore
            self.permissionRecentActivityStore = permissionRecentActivityStore
            self.permissionSiteActivityStore = permissionSiteActivityStore
            self.permissionCleanupService = permissionCleanupService
            self.blockedPopupStore = blockedPopupStore
            self.externalAppResolver = externalAppResolver
            self.externalSchemeSessionStore = externalSchemeSessionStore
            self.permissionBridgeOverrides = permissionBridgeOverrides
        }
    }

    let systemPermissionService: any SumiSystemPermissionService
    let permissionCoordinator: any SumiPermissionCoordinating
    let geolocationProvider: (any SumiGeolocationProviding)?
    let runtimePermissionController: any SumiRuntimePermissionControlling
    let permissionRecentActivityStore: SumiPermissionRecentActivityStore
    let permissionSiteActivityStore: SumiPermissionSiteActivityStore
    let permissionCleanupService: SumiPermissionCleanupService
    let permissionBridges: BrowserPermissionBridgeRegistry

    var webKitPermissionBridge: SumiWebKitPermissionBridge {
        permissionBridges.webKitPermissionBridge
    }
    var webKitGeolocationBridge: SumiWebKitGeolocationBridge {
        permissionBridges.webKitGeolocationBridge
    }
    var notificationPermissionBridge: SumiNotificationPermissionBridge {
        permissionBridges.notificationPermissionBridge
    }
    var filePickerPermissionBridge: SumiFilePickerPermissionBridge {
        permissionBridges.filePickerPermissionBridge
    }
    var storageAccessPermissionBridge: SumiStorageAccessPermissionBridge {
        permissionBridges.storageAccessPermissionBridge
    }
    var permissionIndicatorEventStore: SumiPermissionIndicatorEventStore {
        permissionBridges.permissionIndicatorEventStore
    }
    var blockedPopupStore: SumiBlockedPopupStore {
        permissionBridges.blockedPopupStore
    }
    var popupPermissionBridge: SumiPopupPermissionBridge {
        permissionBridges.popupPermissionBridge
    }
    var externalAppResolver: any SumiExternalAppResolving {
        permissionBridges.externalAppResolver
    }
    var externalSchemeSessionStore: SumiExternalSchemeSessionStore {
        permissionBridges.externalSchemeSessionStore
    }
    var externalSchemePermissionBridge: SumiExternalSchemePermissionBridge {
        permissionBridges.externalSchemePermissionBridge
    }
    var permissionLifecycleController: SumiPermissionGrantLifecycleController {
        permissionBridges.permissionLifecycleController
    }

    private var permissionEventOwner: SumiPermissionEventOwner?
    private var didPauseGeolocationForApplicationBackground = false

    init(dependencies: Dependencies) {
        let persistentPermissionStore = SwiftDataPermissionStore(
            container: dependencies.startupPersistence.container
        )
        let antiAbuseStore = SumiPermissionAntiAbuseStore()
        let systemPermissionService = dependencies.systemPermissionService
            ?? MacSumiSystemPermissionService()
        let permissionCoordinator = dependencies.permissionCoordinator
            ?? SumiPermissionCoordinator(
                policyResolver: DefaultSumiPermissionPolicyResolver(
                    systemPermissionService: systemPermissionService
                ),
                persistentStore: persistentPermissionStore,
                antiAbuseStore: antiAbuseStore,
                sessionOwnerId: "browser"
            )
        let geolocationProvider = dependencies.geolocationProvider
            ?? SumiGeolocationProvider(browserConfiguration: dependencies.browserConfiguration)
        let runtimePermissionController = dependencies.runtimePermissionController
            ?? SumiRuntimePermissionController(geolocationProvider: geolocationProvider)
        let notificationService = dependencies.notificationService ?? SumiNotificationService()
        let filePickerPanelPresenter = dependencies.filePickerPanelPresenter
            ?? SumiFilePickerPanelPresenter()
        let permissionIndicatorEventStore = dependencies.permissionIndicatorEventStore
            ?? SumiPermissionIndicatorEventStore()
        let permissionRecentActivityStore = dependencies.permissionRecentActivityStore
            ?? SumiPermissionRecentActivityStore()
        let permissionCleanupService = dependencies.permissionCleanupService
            ?? SumiPermissionCleanupService(
                store: persistentPermissionStore,
                recentActivityStore: permissionRecentActivityStore,
                antiAbuseStore: antiAbuseStore
            )
        let blockedPopupStore = dependencies.blockedPopupStore ?? SumiBlockedPopupStore()
        let externalSchemeSessionStore = dependencies.externalSchemeSessionStore
            ?? SumiExternalSchemeSessionStore()

        self.systemPermissionService = systemPermissionService
        self.permissionCoordinator = permissionCoordinator
        self.geolocationProvider = geolocationProvider
        self.runtimePermissionController = runtimePermissionController
        self.permissionRecentActivityStore = permissionRecentActivityStore
        self.permissionSiteActivityStore = dependencies.permissionSiteActivityStore
        self.permissionCleanupService = permissionCleanupService
        self.permissionBridges = BrowserPermissionBridgeRegistry(
            dependencies: BrowserPermissionBridgeRegistry.Dependencies(
                permissionCoordinator: permissionCoordinator,
                geolocationProvider: geolocationProvider,
                notificationService: notificationService,
                runtimePermissionController: runtimePermissionController,
                filePickerPanelPresenter: filePickerPanelPresenter,
                permissionIndicatorEventStore: permissionIndicatorEventStore,
                permissionSiteActivityStore: dependencies.permissionSiteActivityStore,
                blockedPopupStore: blockedPopupStore,
                externalAppResolver: dependencies.externalAppResolver,
                externalSchemeSessionStore: externalSchemeSessionStore,
                overrides: dependencies.permissionBridgeOverrides
            )
        )
    }

    func startPermissionEventObservation(
        onPermissionEvent: @escaping SumiPermissionEventOwner.EventHandler
    ) {
        guard permissionEventOwner == nil else { return }
        permissionEventOwner = SumiPermissionEventOwner(
            coordinator: permissionCoordinator,
            recentActivityStore: permissionRecentActivityStore,
            siteActivityStore: permissionSiteActivityStore,
            onEvent: onPermissionEvent
        )
    }

    func pauseGeolocationOnAppBackgroundIfNeeded() {
        guard let geolocationProvider,
              geolocationProvider.currentState == .active
        else { return }

        didPauseGeolocationForApplicationBackground = geolocationProvider.pause() == .paused
    }

    func resumeGeolocationOnAppForegroundIfNeeded() {
        guard didPauseGeolocationForApplicationBackground else { return }

        didPauseGeolocationForApplicationBackground = false
        _ = geolocationProvider?.resume()
    }

    func cancelPermissionEventObservation() {
        permissionEventOwner?.cancel()
        permissionEventOwner = nil
    }

    isolated deinit {
        permissionEventOwner?.cancel()
    }
}
