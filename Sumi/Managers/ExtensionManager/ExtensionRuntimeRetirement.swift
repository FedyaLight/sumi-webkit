import Foundation

/// Executes one extension-scoped retirement and removes its published action
/// state only after every profile binding has been retired successfully.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeRetirement {
    private let scopedRetirement: ExtensionScopedRuntimeRetirement
    private let actionSurfaces: ExtensionActionSurfacePublisher
    private let attachedRetirement:
        ExtensionBrowserAttachmentAuthority.Retirement
    private let nativeMessagingOwners:
        ExtensionDemandScopedNativeMessagingOwners

    init(
        scopedRetirement: ExtensionScopedRuntimeRetirement,
        actionSurfaces: ExtensionActionSurfacePublisher,
        attachedRetirement:
            ExtensionBrowserAttachmentAuthority.Retirement,
        nativeMessagingOwners:
            ExtensionDemandScopedNativeMessagingOwners
    ) {
        self.scopedRetirement = scopedRetirement
        self.actionSurfaces = actionSurfaces
        self.attachedRetirement = attachedRetirement
        self.nativeMessagingOwners = nativeMessagingOwners
    }

    func retire(
        extensionID: String,
        cause: ExtensionScopedRuntimeRetirement.Cause,
        mutationLease: ExtensionRuntimeMutationLease
    ) -> ExtensionScopedRuntimeRetirement.Result {
        let result = attachedRetirement.retire(
            using: scopedRetirement,
            extensionID: extensionID,
            cause: cause,
            admission: .mutation(mutationLease),
            nativeMessagingOwners: nativeMessagingOwners
        )
        if result.completed {
            actionSurfaces.clearActionSurfaceState(for: extensionID)
        }
        return result
    }

    func cleanUpAfterQuiescentRollback(
        extensionID: String,
        claim: ExtensionContextLoadClaim,
        mutationLease: ExtensionRuntimeMutationLease?
    ) -> ExtensionScopedRuntimeRetirement.Result {
        let result = attachedRetirement.retire(
            using: scopedRetirement,
            extensionID: extensionID,
            cause: .runtimeRollback,
            admission: .rollback(claim, mutationLease),
            nativeMessagingOwners: nativeMessagingOwners
        )
        if result.completed {
            actionSurfaces.clearActionSurfaceState(for: extensionID)
        }
        return result
    }
}
