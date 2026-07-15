import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeReloadProfileReconciler {
    private let profileRuntime: ExtensionProfileRuntime
    private let reconciler: ExtensionProfileWebViewRuntimeReconciler

    init(
        profileRuntime: ExtensionProfileRuntime,
        reconciler: ExtensionProfileWebViewRuntimeReconciler
    ) {
        self.profileRuntime = profileRuntime
        self.reconciler = reconciler
    }

    func profileIDs(including requestedProfileID: UUID?) -> Set<UUID> {
        var profileIDs = Set(profileRuntime.controllersByProfile.keys)
        if let requestedProfileID { profileIDs.insert(requestedProfileID) }
        if let currentProfileID = profileRuntime.currentProfileId {
            profileIDs.insert(currentProfileID)
        }
        return profileIDs
    }

    func reconcile(
        profileID: UUID,
        publicationStage: ExtensionRuntimePublicationStage,
        reason: String
    ) {
        reconciler.reconcile(
            profileID: profileID,
            publicationStage: publicationStage,
            reason: reason
        )
    }
}
