import Foundation

@MainActor
enum BrowserAuxiliaryWindowCompositionFactory {
    static func make(
        browserManager: BrowserManager,
        teardownRegistry: AuxiliaryWindowTeardownRegistry
    ) -> BrowserAuxiliaryWindowComposition {
        let shellRuntime = browserManager.shellRuntime
        let tabManager = browserManager.tabManager
        let webViewOwnership = browserManager.webViewRuntime.ownershipService
        let websiteDataCleanup = browserManager.webViewRuntime
            .websiteDataCleanupService
        let composition = BrowserAuxiliaryWindowComposition(
            windowRegistry: { [weak shellRuntime] in
                shellRuntime?.windowRegistry
            },
            currentProfile: { [weak tabManager] in
                tabManager?.runtimePorts?.currentProfileId
            },
            spaces: tabManager.spaceStateOwner,
            tabContext: shellRuntime.windowTabs,
            transientTabs: tabManager.transientWebKitTabLifecycleOwner,
            webViewOwnership: webViewOwnership,
            extensions: browserManager.optionalModules.extensions,
            popupPermissions: browserManager.permissionRuntime
                .popupPermissionBridge,
            filePickerPermissions: browserManager.permissionRuntime
                .filePickerPermissionBridge,
            mutationAdmission: websiteDataCleanup
        )
        teardownRegistry.register(composition.teardown)
        return composition
    }
}
