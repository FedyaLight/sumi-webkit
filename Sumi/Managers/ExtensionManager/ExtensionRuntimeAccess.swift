import Foundation
import WebKit

/// Shared runtime-access collaborator for extension runtime flows.
/// Carries profile resolution and controller provisioning shared by flows.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeAccess {
    let profileRuntime: ExtensionProfileRuntime
    let controllerProvisioningOwner: ExtensionControllerProvisioningOwner
    let runtime: @MainActor () -> ExtensionManagerRuntime

    init(
        profileRuntime: ExtensionProfileRuntime,
        controllerProvisioningOwner: ExtensionControllerProvisioningOwner,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime
    ) {
        self.profileRuntime = profileRuntime
        self.controllerProvisioningOwner = controllerProvisioningOwner
        self.runtime = runtime
    }

    func fallbackProfileId() -> UUID? {
        resolvedProfileId(nil)
    }

    func resolvedProfileId(_ explicitProfileId: UUID?) -> UUID? {
        profileRuntime.resolvedProfileId(
            explicitProfileId: explicitProfileId,
            runtime: runtime()
        )
    }

    func ensureExtensionController(_ profileId: UUID) {
        _ = controllerProvisioningOwner.ensureExtensionController(for: profileId)
    }

    func getExtensionContext(
        _ extensionId: String,
        _ profileId: UUID
    ) -> WKWebExtensionContext? {
        profileRuntime.contexts(for: profileId)[extensionId]
    }

    func getExtensionContext(
        _ extensionId: String,
        _ profileId: UUID?
    ) -> WKWebExtensionContext? {
        guard let resolvedProfileId = resolvedProfileId(profileId) else { return nil }
        return profileRuntime.contexts(for: resolvedProfileId)[extensionId]
    }
}
