import Foundation
import WebKit

/// Shared runtime-access collaborator for extension flow owners
/// (`ExtensionInstallationFlowOwner`, `ExtensionActionClickFlowOwner`).
/// Holds the profile / controller / session / runtime seam so those owners
/// do not each re-shim the same sibling-owner call shape.
@available(macOS 15.5, *)
@MainActor
final class ExtensionFlowOwnerRuntimeAccess {
    let profileRuntimeOwner: ExtensionProfileRuntimeOwner
    let controllerProvisioningOwner: ExtensionControllerProvisioningOwner
    let runtimeSessionOwner: ExtensionRuntimeSessionOwner
    let runtime: @MainActor () -> ExtensionManagerRuntime

    init(
        profileRuntimeOwner: ExtensionProfileRuntimeOwner,
        controllerProvisioningOwner: ExtensionControllerProvisioningOwner,
        runtimeSessionOwner: ExtensionRuntimeSessionOwner,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime
    ) {
        self.profileRuntimeOwner = profileRuntimeOwner
        self.controllerProvisioningOwner = controllerProvisioningOwner
        self.runtimeSessionOwner = runtimeSessionOwner
        self.runtime = runtime
    }

    func fallbackProfileId() -> UUID? {
        resolvedProfileId(nil)
    }

    func resolvedProfileId(_ explicitProfileId: UUID?) -> UUID? {
        profileRuntimeOwner.resolvedProfileId(
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
        profileRuntimeOwner.contexts(for: profileId)[extensionId]
    }

    func getExtensionContext(
        _ extensionId: String,
        _ profileId: UUID?
    ) -> WKWebExtensionContext? {
        guard let resolvedProfileId = resolvedProfileId(profileId) else { return nil }
        return profileRuntimeOwner.contexts(for: resolvedProfileId)[extensionId]
    }

    func recordExtensionLoadError(
        _ error: Error,
        _ extensionId: String,
        _ profileId: UUID
    ) {
        runtimeSessionOwner.lastExtensionLoadErrors[
            ExtensionRuntimeResidencyState.scopedKey(
                extensionId: extensionId,
                profileId: profileId
            )
        ] = error
    }

    func clearExtensionLoadError(_ extensionId: String, _ profileId: UUID) {
        runtimeSessionOwner.lastExtensionLoadErrors.removeValue(
            forKey: ExtensionRuntimeResidencyState.scopedKey(
                extensionId: extensionId,
                profileId: profileId
            )
        )
    }

    func lastExtensionLoadError(
        _ extensionId: String,
        _ profileId: UUID
    ) -> Error? {
        runtimeSessionOwner.lastExtensionLoadErrors[
            ExtensionRuntimeResidencyState.scopedKey(
                extensionId: extensionId,
                profileId: profileId
            )
        ]
    }
}
