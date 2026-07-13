import Foundation

/// Executes one extension-scoped retirement and removes its published action
/// state only after every profile binding has been retired successfully.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeRetirement {
    private let scopedRetirement: ExtensionScopedRuntimeRetirement
    private let actionSurfaces: @MainActor () ->
        ExtensionActionSurfacePublisher?
    private let resources: @MainActor () ->
        ExtensionScopedRuntimeRetirement.Resources

    init(
        scopedRetirement: ExtensionScopedRuntimeRetirement,
        actionSurfaces: @escaping @MainActor () ->
            ExtensionActionSurfacePublisher?,
        resources: @escaping @MainActor () ->
            ExtensionScopedRuntimeRetirement.Resources
    ) {
        self.scopedRetirement = scopedRetirement
        self.actionSurfaces = actionSurfaces
        self.resources = resources
    }

    func retire(
        extensionID: String,
        cause: ExtensionScopedRuntimeRetirement.Cause,
        mutationLease: ExtensionRuntimeMutationLease
    ) -> ExtensionScopedRuntimeRetirement.Result {
        let result = scopedRetirement.retire(
            extensionID: extensionID,
            cause: cause,
            admission: .mutation(mutationLease),
            resources: resources()
        )
        if result.completed {
            actionSurfaces()?.clearActionSurfaceState(for: extensionID)
        }
        return result
    }

    func cleanUpAfterQuiescentRollback(
        extensionID: String,
        claim: ExtensionContextLoadClaim,
        mutationLease: ExtensionRuntimeMutationLease?
    ) -> ExtensionScopedRuntimeRetirement.Result {
        let result = scopedRetirement.retire(
            extensionID: extensionID,
            cause: .runtimeRollback,
            admission: .rollback(claim, mutationLease),
            resources: resources()
        )
        if result.completed {
            actionSurfaces()?.clearActionSurfaceState(for: extensionID)
        }
        return result
    }
}
