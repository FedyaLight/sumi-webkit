import Foundation

@MainActor
final class BrowserPermissionBridgeRegistry {
    struct Overrides {
        let webKitPermissionBridge: SumiWebKitPermissionBridge?
        let webKitGeolocationBridge: SumiWebKitGeolocationBridge?
        let notificationPermissionBridge: SumiNotificationPermissionBridge?
        let filePickerPermissionBridge: SumiFilePickerPermissionBridge?
        let storageAccessPermissionBridge: SumiStorageAccessPermissionBridge?
        let popupPermissionBridge: SumiPopupPermissionBridge?
        let externalSchemePermissionBridge: SumiExternalSchemePermissionBridge?

        init(
            webKitPermissionBridge: SumiWebKitPermissionBridge? = nil,
            webKitGeolocationBridge: SumiWebKitGeolocationBridge? = nil,
            notificationPermissionBridge: SumiNotificationPermissionBridge? = nil,
            filePickerPermissionBridge: SumiFilePickerPermissionBridge? = nil,
            storageAccessPermissionBridge: SumiStorageAccessPermissionBridge? = nil,
            popupPermissionBridge: SumiPopupPermissionBridge? = nil,
            externalSchemePermissionBridge: SumiExternalSchemePermissionBridge? = nil
        ) {
            self.webKitPermissionBridge = webKitPermissionBridge
            self.webKitGeolocationBridge = webKitGeolocationBridge
            self.notificationPermissionBridge = notificationPermissionBridge
            self.filePickerPermissionBridge = filePickerPermissionBridge
            self.storageAccessPermissionBridge = storageAccessPermissionBridge
            self.popupPermissionBridge = popupPermissionBridge
            self.externalSchemePermissionBridge = externalSchemePermissionBridge
        }
    }

    struct Dependencies {
        let permissionCoordinator: any SumiPermissionCoordinating
        let geolocationProvider: (any SumiGeolocationProviding)?
        let notificationService: any SumiNotificationServicing
        let runtimePermissionController: any SumiRuntimePermissionControlling
        let filePickerPanelPresenter: any SumiFilePickerPanelPresenting
        let permissionIndicatorEventStore: SumiPermissionIndicatorEventStore
        let permissionSiteActivityStore: SumiPermissionSiteActivityStore
        let blockedPopupStore: SumiBlockedPopupStore
        let externalAppResolver: any SumiExternalAppResolving
        let externalSchemeSessionStore: SumiExternalSchemeSessionStore
        let overrides: Overrides

        init(
            permissionCoordinator: any SumiPermissionCoordinating,
            geolocationProvider: (any SumiGeolocationProviding)?,
            notificationService: any SumiNotificationServicing,
            runtimePermissionController: any SumiRuntimePermissionControlling,
            filePickerPanelPresenter: any SumiFilePickerPanelPresenting,
            permissionIndicatorEventStore: SumiPermissionIndicatorEventStore,
            permissionSiteActivityStore: SumiPermissionSiteActivityStore,
            blockedPopupStore: SumiBlockedPopupStore,
            externalAppResolver: any SumiExternalAppResolving,
            externalSchemeSessionStore: SumiExternalSchemeSessionStore,
            overrides: Overrides = Overrides()
        ) {
            self.permissionCoordinator = permissionCoordinator
            self.geolocationProvider = geolocationProvider
            self.notificationService = notificationService
            self.runtimePermissionController = runtimePermissionController
            self.filePickerPanelPresenter = filePickerPanelPresenter
            self.permissionIndicatorEventStore = permissionIndicatorEventStore
            self.permissionSiteActivityStore = permissionSiteActivityStore
            self.blockedPopupStore = blockedPopupStore
            self.externalAppResolver = externalAppResolver
            self.externalSchemeSessionStore = externalSchemeSessionStore
            self.overrides = overrides
        }
    }

    let webKitPermissionBridge: SumiWebKitPermissionBridge
    let webKitGeolocationBridge: SumiWebKitGeolocationBridge
    let notificationPermissionBridge: SumiNotificationPermissionBridge
    let filePickerPermissionBridge: SumiFilePickerPermissionBridge
    let storageAccessPermissionBridge: SumiStorageAccessPermissionBridge
    let permissionIndicatorEventStore: SumiPermissionIndicatorEventStore
    let blockedPopupStore: SumiBlockedPopupStore
    let popupPermissionBridge: SumiPopupPermissionBridge
    let externalAppResolver: any SumiExternalAppResolving
    let externalSchemeSessionStore: SumiExternalSchemeSessionStore
    let externalSchemePermissionBridge: SumiExternalSchemePermissionBridge
    let permissionLifecycleController: SumiPermissionGrantLifecycleController

    init(dependencies: Dependencies) {
        let coordinator = dependencies.permissionCoordinator
        let filePickerPermissionBridge = dependencies.overrides.filePickerPermissionBridge
            ?? SumiFilePickerPermissionBridge(
                coordinator: coordinator,
                panelPresenter: dependencies.filePickerPanelPresenter,
                indicatorEventStore: dependencies.permissionIndicatorEventStore
            )

        self.webKitPermissionBridge = dependencies.overrides.webKitPermissionBridge
            ?? SumiWebKitPermissionBridge(
                coordinator: coordinator,
                runtimeController: dependencies.runtimePermissionController
            )
        self.webKitGeolocationBridge = dependencies.overrides.webKitGeolocationBridge
            ?? SumiWebKitGeolocationBridge(
                coordinator: coordinator,
                geolocationProvider: dependencies.geolocationProvider
            )
        self.notificationPermissionBridge = dependencies.overrides.notificationPermissionBridge
            ?? SumiNotificationPermissionBridge(
                coordinator: coordinator,
                notificationService: dependencies.notificationService,
                indicatorEventStore: dependencies.permissionIndicatorEventStore
            )
        self.filePickerPermissionBridge = filePickerPermissionBridge
        self.storageAccessPermissionBridge = dependencies.overrides.storageAccessPermissionBridge
            ?? SumiStorageAccessPermissionBridge(
                coordinator: coordinator,
                indicatorEventStore: dependencies.permissionIndicatorEventStore
            )
        self.permissionIndicatorEventStore = dependencies.permissionIndicatorEventStore
        self.blockedPopupStore = dependencies.blockedPopupStore
        self.popupPermissionBridge = dependencies.overrides.popupPermissionBridge
            ?? SumiPopupPermissionBridge(
                coordinator: coordinator,
                blockedPopupStore: dependencies.blockedPopupStore,
                siteActivityStore: dependencies.permissionSiteActivityStore
            )
        self.externalAppResolver = dependencies.externalAppResolver
        self.externalSchemeSessionStore = dependencies.externalSchemeSessionStore
        self.externalSchemePermissionBridge = dependencies.overrides.externalSchemePermissionBridge
            ?? SumiExternalSchemePermissionBridge(
                coordinator: coordinator,
                appResolver: dependencies.externalAppResolver,
                sessionStore: dependencies.externalSchemeSessionStore
            )
        self.permissionLifecycleController = SumiPermissionGrantLifecycleController(
            coordinator: coordinator,
            geolocationProvider: dependencies.geolocationProvider,
            filePickerBridge: filePickerPermissionBridge,
            indicatorEventStore: dependencies.permissionIndicatorEventStore,
            blockedPopupStore: dependencies.blockedPopupStore,
            externalSchemeSessionStore: dependencies.externalSchemeSessionStore
        )
    }
}
