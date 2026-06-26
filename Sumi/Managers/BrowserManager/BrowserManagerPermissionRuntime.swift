import SwiftData

@MainActor
final class BrowserManagerPermissionRuntime {
    struct Dependencies {
        let startupPersistence: BrowserManagerStartupPersistence
        let systemPermissionService: (any SumiSystemPermissionService)?
        let permissionCoordinator: (any SumiPermissionCoordinating)?
        let geolocationProvider: (any SumiGeolocationProviding)?
        let notificationService: (any SumiNotificationServicing)?
        let runtimePermissionController: (any SumiRuntimePermissionControlling)?
        let webKitPermissionBridge: SumiWebKitPermissionBridge?
        let webKitGeolocationBridge: SumiWebKitGeolocationBridge?
        let notificationPermissionBridge: SumiNotificationPermissionBridge?
        let filePickerPanelPresenter: (any SumiFilePickerPanelPresenting)?
        let filePickerPermissionBridge: SumiFilePickerPermissionBridge?
        let storageAccessPermissionBridge: SumiStorageAccessPermissionBridge?
        let permissionIndicatorEventStore: SumiPermissionIndicatorEventStore?
        let permissionRecentActivityStore: SumiPermissionRecentActivityStore?
        let permissionSiteActivityStore: SumiPermissionSiteActivityStore?
        let permissionCleanupService: SumiPermissionCleanupService?
        let blockedPopupStore: SumiBlockedPopupStore?
        let popupPermissionBridge: SumiPopupPermissionBridge?
        let externalAppResolver: (any SumiExternalAppResolving)?
        let externalSchemeSessionStore: SumiExternalSchemeSessionStore?
        let externalSchemePermissionBridge: SumiExternalSchemePermissionBridge?

        init(
            startupPersistence: BrowserManagerStartupPersistence,
            systemPermissionService: (any SumiSystemPermissionService)? = nil,
            permissionCoordinator: (any SumiPermissionCoordinating)? = nil,
            geolocationProvider: (any SumiGeolocationProviding)? = nil,
            notificationService: (any SumiNotificationServicing)? = nil,
            runtimePermissionController: (any SumiRuntimePermissionControlling)? = nil,
            webKitPermissionBridge: SumiWebKitPermissionBridge? = nil,
            webKitGeolocationBridge: SumiWebKitGeolocationBridge? = nil,
            notificationPermissionBridge: SumiNotificationPermissionBridge? = nil,
            filePickerPanelPresenter: (any SumiFilePickerPanelPresenting)? = nil,
            filePickerPermissionBridge: SumiFilePickerPermissionBridge? = nil,
            storageAccessPermissionBridge: SumiStorageAccessPermissionBridge? = nil,
            permissionIndicatorEventStore: SumiPermissionIndicatorEventStore? = nil,
            permissionRecentActivityStore: SumiPermissionRecentActivityStore? = nil,
            permissionSiteActivityStore: SumiPermissionSiteActivityStore? = nil,
            permissionCleanupService: SumiPermissionCleanupService? = nil,
            blockedPopupStore: SumiBlockedPopupStore? = nil,
            popupPermissionBridge: SumiPopupPermissionBridge? = nil,
            externalAppResolver: (any SumiExternalAppResolving)? = nil,
            externalSchemeSessionStore: SumiExternalSchemeSessionStore? = nil,
            externalSchemePermissionBridge: SumiExternalSchemePermissionBridge? = nil
        ) {
            self.startupPersistence = startupPersistence
            self.systemPermissionService = systemPermissionService
            self.permissionCoordinator = permissionCoordinator
            self.geolocationProvider = geolocationProvider
            self.notificationService = notificationService
            self.runtimePermissionController = runtimePermissionController
            self.webKitPermissionBridge = webKitPermissionBridge
            self.webKitGeolocationBridge = webKitGeolocationBridge
            self.notificationPermissionBridge = notificationPermissionBridge
            self.filePickerPanelPresenter = filePickerPanelPresenter
            self.filePickerPermissionBridge = filePickerPermissionBridge
            self.storageAccessPermissionBridge = storageAccessPermissionBridge
            self.permissionIndicatorEventStore = permissionIndicatorEventStore
            self.permissionRecentActivityStore = permissionRecentActivityStore
            self.permissionSiteActivityStore = permissionSiteActivityStore
            self.permissionCleanupService = permissionCleanupService
            self.blockedPopupStore = blockedPopupStore
            self.popupPermissionBridge = popupPermissionBridge
            self.externalAppResolver = externalAppResolver
            self.externalSchemeSessionStore = externalSchemeSessionStore
            self.externalSchemePermissionBridge = externalSchemePermissionBridge
        }
    }

    let systemPermissionService: any SumiSystemPermissionService
    let permissionCoordinator: any SumiPermissionCoordinating
    let geolocationProvider: (any SumiGeolocationProviding)?
    let runtimePermissionController: any SumiRuntimePermissionControlling
    let webKitPermissionBridge: SumiWebKitPermissionBridge
    let webKitGeolocationBridge: SumiWebKitGeolocationBridge
    let notificationPermissionBridge: SumiNotificationPermissionBridge
    let filePickerPermissionBridge: SumiFilePickerPermissionBridge
    let storageAccessPermissionBridge: SumiStorageAccessPermissionBridge
    let permissionIndicatorEventStore: SumiPermissionIndicatorEventStore
    let permissionRecentActivityStore: SumiPermissionRecentActivityStore
    let permissionSiteActivityStore: SumiPermissionSiteActivityStore
    let permissionCleanupService: SumiPermissionCleanupService
    let blockedPopupStore: SumiBlockedPopupStore
    let popupPermissionBridge: SumiPopupPermissionBridge
    let externalAppResolver: any SumiExternalAppResolving
    let externalSchemeSessionStore: SumiExternalSchemeSessionStore
    let externalSchemePermissionBridge: SumiExternalSchemePermissionBridge
    let permissionLifecycleController: SumiPermissionGrantLifecycleController
    let permissionSidebarPinningController = SumiPermissionSidebarPinningController()

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
            ?? SumiGeolocationProvider(browserConfiguration: BrowserConfiguration.shared)
        let runtimePermissionController = dependencies.runtimePermissionController
            ?? SumiRuntimePermissionController(geolocationProvider: geolocationProvider)
        let notificationService = dependencies.notificationService ?? SumiNotificationService()
        let filePickerPanelPresenter = dependencies.filePickerPanelPresenter
            ?? SumiFilePickerPanelPresenter()
        let permissionIndicatorEventStore = dependencies.permissionIndicatorEventStore
            ?? SumiPermissionIndicatorEventStore()
        let permissionRecentActivityStore = dependencies.permissionRecentActivityStore
            ?? SumiPermissionRecentActivityStore()
        let permissionSiteActivityStore = dependencies.permissionSiteActivityStore
            ?? SumiPermissionSiteActivityStore.shared
        let permissionCleanupService = dependencies.permissionCleanupService
            ?? SumiPermissionCleanupService(
                store: persistentPermissionStore,
                recentActivityStore: permissionRecentActivityStore,
                antiAbuseStore: antiAbuseStore
            )
        let blockedPopupStore = dependencies.blockedPopupStore ?? SumiBlockedPopupStore()
        let externalAppResolver = dependencies.externalAppResolver
            ?? SumiNSWorkspaceExternalAppResolver.shared
        let externalSchemeSessionStore = dependencies.externalSchemeSessionStore
            ?? SumiExternalSchemeSessionStore()

        self.systemPermissionService = systemPermissionService
        self.permissionCoordinator = permissionCoordinator
        self.geolocationProvider = geolocationProvider
        self.runtimePermissionController = runtimePermissionController
        self.webKitPermissionBridge = dependencies.webKitPermissionBridge
            ?? SumiWebKitPermissionBridge(
                coordinator: permissionCoordinator,
                runtimeController: runtimePermissionController
            )
        self.webKitGeolocationBridge = dependencies.webKitGeolocationBridge
            ?? SumiWebKitGeolocationBridge(
                coordinator: permissionCoordinator,
                geolocationProvider: geolocationProvider
            )
        self.notificationPermissionBridge = dependencies.notificationPermissionBridge
            ?? SumiNotificationPermissionBridge(
                coordinator: permissionCoordinator,
                notificationService: notificationService,
                indicatorEventStore: permissionIndicatorEventStore
            )
        let resolvedFilePickerPermissionBridge = dependencies.filePickerPermissionBridge
            ?? SumiFilePickerPermissionBridge(
                coordinator: permissionCoordinator,
                panelPresenter: filePickerPanelPresenter,
                indicatorEventStore: permissionIndicatorEventStore
            )
        self.filePickerPermissionBridge = resolvedFilePickerPermissionBridge
        self.storageAccessPermissionBridge = dependencies.storageAccessPermissionBridge
            ?? SumiStorageAccessPermissionBridge(
                coordinator: permissionCoordinator,
                indicatorEventStore: permissionIndicatorEventStore
            )
        self.permissionIndicatorEventStore = permissionIndicatorEventStore
        self.permissionRecentActivityStore = permissionRecentActivityStore
        self.permissionSiteActivityStore = permissionSiteActivityStore
        self.permissionCleanupService = permissionCleanupService
        self.blockedPopupStore = blockedPopupStore
        self.popupPermissionBridge = dependencies.popupPermissionBridge
            ?? SumiPopupPermissionBridge(
                coordinator: permissionCoordinator,
                blockedPopupStore: blockedPopupStore,
                siteActivityStore: permissionSiteActivityStore
            )
        self.externalAppResolver = externalAppResolver
        self.externalSchemeSessionStore = externalSchemeSessionStore
        self.externalSchemePermissionBridge = dependencies.externalSchemePermissionBridge
            ?? SumiExternalSchemePermissionBridge(
                coordinator: permissionCoordinator,
                appResolver: externalAppResolver,
                sessionStore: externalSchemeSessionStore
            )
        self.permissionLifecycleController = SumiPermissionGrantLifecycleController(
            coordinator: permissionCoordinator,
            geolocationProvider: geolocationProvider,
            filePickerBridge: resolvedFilePickerPermissionBridge,
            indicatorEventStore: permissionIndicatorEventStore,
            blockedPopupStore: blockedPopupStore,
            externalSchemeSessionStore: externalSchemeSessionStore
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

    func pauseGeolocationForApplicationBackgroundIfNeeded() {
        guard let geolocationProvider,
              geolocationProvider.currentState == .active
        else { return }

        didPauseGeolocationForApplicationBackground = geolocationProvider.pause() == .paused
    }

    func resumeGeolocationForApplicationForegroundIfNeeded() {
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
