@MainActor
extension BrowserManager {
    var permissionBridges: BrowserPermissionBridgeRegistry {
        permissionRuntime.permissionBridges
    }

    var systemPermissionService: any SumiSystemPermissionService {
        permissionRuntime.systemPermissionService
    }

    var permissionCoordinator: any SumiPermissionCoordinating {
        permissionRuntime.permissionCoordinator
    }

    var runtimePermissionController: any SumiRuntimePermissionControlling {
        permissionRuntime.runtimePermissionController
    }

    var webKitPermissionBridge: SumiWebKitPermissionBridge {
        permissionRuntime.webKitPermissionBridge
    }

    var webKitGeolocationBridge: SumiWebKitGeolocationBridge {
        permissionRuntime.webKitGeolocationBridge
    }

    var notificationPermissionBridge: SumiNotificationPermissionBridge {
        permissionRuntime.notificationPermissionBridge
    }

    var filePickerPermissionBridge: SumiFilePickerPermissionBridge {
        permissionRuntime.filePickerPermissionBridge
    }

    var storageAccessPermissionBridge: SumiStorageAccessPermissionBridge {
        permissionRuntime.storageAccessPermissionBridge
    }

    var permissionIndicatorEventStore: SumiPermissionIndicatorEventStore {
        permissionRuntime.permissionIndicatorEventStore
    }

    var permissionRecentActivityStore: SumiPermissionRecentActivityStore {
        permissionRuntime.permissionRecentActivityStore
    }

    var permissionSiteActivityStore: SumiPermissionSiteActivityStore {
        permissionRuntime.permissionSiteActivityStore
    }

    var permissionCleanupService: SumiPermissionCleanupService {
        permissionRuntime.permissionCleanupService
    }

    var blockedPopupStore: SumiBlockedPopupStore {
        permissionRuntime.blockedPopupStore
    }

    var popupPermissionBridge: SumiPopupPermissionBridge {
        permissionRuntime.popupPermissionBridge
    }

    var externalAppResolver: any SumiExternalAppResolving {
        permissionRuntime.externalAppResolver
    }

    var externalSchemeSessionStore: SumiExternalSchemeSessionStore {
        permissionRuntime.externalSchemeSessionStore
    }

    var externalSchemePermissionBridge: SumiExternalSchemePermissionBridge {
        permissionRuntime.externalSchemePermissionBridge
    }

    var permissionLifecycleController: SumiPermissionGrantLifecycleController {
        permissionRuntime.permissionLifecycleController
    }
}
