import Foundation
import WebKit

/// Shared runtime-access collaborator for extension runtime flows.
/// Carries the profile, controller, session, and runtime seam shared by flows.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeAccess {
    let profileRuntime: ExtensionProfileRuntime
    let controllerProvisioningOwner: ExtensionControllerProvisioningOwner
    let runtimeSession: ExtensionRuntimeSession
    let runtime: @MainActor () -> ExtensionManagerRuntime

    init(
        profileRuntime: ExtensionProfileRuntime,
        controllerProvisioningOwner: ExtensionControllerProvisioningOwner,
        runtimeSession: ExtensionRuntimeSession,
        runtime: @escaping @MainActor () -> ExtensionManagerRuntime
    ) {
        self.profileRuntime = profileRuntime
        self.controllerProvisioningOwner = controllerProvisioningOwner
        self.runtimeSession = runtimeSession
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

    func recordExtensionLoadError(
        _ error: Error,
        _ extensionId: String,
        _ profileId: UUID
    ) {
        runtimeSession.lastExtensionLoadErrors[
            ExtensionRuntimeResidencyState.scopedKey(
                extensionId: extensionId,
                profileId: profileId
            )
        ] = error
    }

    func clearExtensionLoadError(_ extensionId: String, _ profileId: UUID) {
        runtimeSession.lastExtensionLoadErrors.removeValue(
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
        runtimeSession.lastExtensionLoadErrors[
            ExtensionRuntimeResidencyState.scopedKey(
                extensionId: extensionId,
                profileId: profileId
            )
        ]
    }
}
