import Foundation

/// Performs terminal profile-scoped extension cleanup after the browser has
/// selected a durable fallback. Context unload is completed before controller
/// and profile keys can be removed.
@available(macOS 15.5, *)
@MainActor
final class ExtensionProfileRuntimeRetirement {
    private let profileRuntime: ExtensionProfileRuntime
    private let websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence
    private let controllerProvisioning: ExtensionControllerProvisioningOwner

    init(
        profileRuntime: ExtensionProfileRuntime,
        websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence,
        controllerProvisioning: ExtensionControllerProvisioningOwner
    ) {
        self.profileRuntime = profileRuntime
        self.websiteDataQuiescence = websiteDataQuiescence
        self.controllerProvisioning = controllerProvisioning
    }

    func retire(profileID: UUID, fallbackProfileID: UUID) -> Bool {
        guard profileRuntime.canRetireProfile(
            profileID,
            fallbackProfileID: fallbackProfileID
        ), websiteDataQuiescence.quiesce(profileIDs: [profileID]),
            let mutationLease = profileRuntime.beginProfileRetirementMigration(
                to: fallbackProfileID
            )
        else { return false }
        defer { _ = profileRuntime.endProfileReferenceMutation(mutationLease) }

        controllerProvisioning.retireProfileController(
            profileID: profileID,
            fallbackProfileID: fallbackProfileID
        )
        return profileRuntime.retireProfile(
            profileID,
            fallbackProfileID: fallbackProfileID,
            mutationLease: mutationLease
        )
    }

    func containsReference(to profileID: UUID) -> Bool {
        profileRuntime.containsProfileReference(to: profileID)
            || controllerProvisioning.containsProfileReference(to: profileID)
    }
}
