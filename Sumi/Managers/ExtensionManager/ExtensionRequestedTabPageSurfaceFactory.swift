import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabPageSurfaceRoles {
    let resolution: ExtensionPageResolutionOwner
    let navigation: ExtensionPageNavigationPreparationOwner
}

/// Creates only page identity and navigation roles.
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
        controller: ExtensionControllerRuntimeComposition
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
        return ExtensionRequestedTabPageSurfaceRoles(
            resolution: resolution,
            navigation: navigation
        )
    }
}
