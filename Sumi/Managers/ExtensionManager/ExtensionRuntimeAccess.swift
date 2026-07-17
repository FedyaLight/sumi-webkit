import Foundation
import WebKit

/// Shared runtime-access collaborator for extension runtime flows.
/// Carries profile resolution and controller provisioning shared by flows.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeAccess {
    let profileRuntime: ExtensionProfileRuntime
    let controllerProvisioningOwner: ExtensionControllerProvisioningOwner

    init(
        profileRuntime: ExtensionProfileRuntime,
        controllerProvisioningOwner: ExtensionControllerProvisioningOwner
    ) {
        self.profileRuntime = profileRuntime
        self.controllerProvisioningOwner = controllerProvisioningOwner
    }

    func fallbackProfileId() -> UUID? {
        resolvedProfileId(nil)
    }

    func resolvedProfileId(_ explicitProfileId: UUID?) -> UUID? {
        explicitProfileId ?? profileRuntime.currentProfileId
    }

    @discardableResult
    func ensureExtensionController(_ profileId: UUID) -> Bool {
        controllerProvisioningOwner.controllerIfAdmitted(for: profileId) != nil
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
