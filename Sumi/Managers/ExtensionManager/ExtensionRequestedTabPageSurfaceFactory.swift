import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabPageSurfaceRoles {
    let resolution: ExtensionPageResolutionOwner
    let navigation: ExtensionPageNavigationPreparationOwner
    let contextMenu: ExtensionPageContextMenuItemsOwner
}

/// Creates only page identity, navigation, and context-menu roles.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabPageSurfaceFactory {
    private let profileRuntime: ExtensionProfileRuntime
    private let installedExtensions: InstalledExtensionCollection
    private let controllerProvisioning: ExtensionControllerProvisioningOwner

    init(
        profileRuntime: ExtensionProfileRuntime,
        installedExtensions: InstalledExtensionCollection,
        controllerProvisioning: ExtensionControllerProvisioningOwner
    ) {
        self.profileRuntime = profileRuntime
        self.installedExtensions = installedExtensions
        self.controllerProvisioning = controllerProvisioning
    }

    func assemble(
        bridge: BrowserExtensionBridgeComposition,
        controller: ExtensionControllerRuntimeComposition,
        windows: ExtensionWindowPublicationAssembly
    ) -> ExtensionRequestedTabPageSurfaceRoles {
        let resolution = ExtensionPageResolutionOwner(
            profileRuntime: profileRuntime,
            installedExtensions: installedExtensions,
            currentProfileID: { bridge.profiles.currentProfile()?.id }
        )
        let navigation = ExtensionPageNavigationPreparationOwner(
            tabProfiles: controller.profiles,
            webViews: controller.webViews,
            controllerProvisioning: controllerProvisioning
        )
        let contextMenu = ExtensionPageContextMenuItemsOwner(
            publishedTabs: windows.tabs.publishedTabs,
            profileRuntime: profileRuntime,
            profileID: { [profiles = controller.profiles] tab in
                profiles.profileID(for: tab)
            },
            adapters: windows.adapters
        )
        return ExtensionRequestedTabPageSurfaceRoles(
            resolution: resolution,
            navigation: navigation,
            contextMenu: contextMenu
        )
    }
}
