import Foundation

/// Ensures one persisted enabled extension is fully active in one profile.
/// Missing bindings are loaded; existing exact bindings are finalized under a
/// fresh claim. Multi-profile policy remains outside this single-profile flow.
@available(macOS 15.5, *)
@MainActor
final class ExtensionEnabledRuntimeActivation {
    private let runtimeAccess: ExtensionRuntimeAccess
    private let authority: ExtensionLoadedContextAuthority
    private let loader: ExtensionRuntimeLoader
    private let finalizer: ExtensionLoadedContextFinalizer

    init(
        runtimeAccess: ExtensionRuntimeAccess,
        authority: ExtensionLoadedContextAuthority,
        loader: ExtensionRuntimeLoader,
        finalizer: ExtensionLoadedContextFinalizer
    ) {
        self.runtimeAccess = runtimeAccess
        self.authority = authority
        self.loader = loader
        self.finalizer = finalizer
    }

    /// Returns the refreshed record when a missing context had to be loaded.
    /// Existing bindings require no metadata rewrite and return `nil`.
    func activate(
        entity: ExtensionEntity,
        profileID: UUID,
        activation: ExtensionLoadedContextFinalizer.Activation,
        mutationLease: ExtensionRuntimeMutationLease?
    ) async throws -> InstalledExtension? {
        runtimeAccess.ensureExtensionController(profileID)
        guard runtimeAccess.getExtensionContext(entity.id, profileID) != nil
        else {
            return try await loader.loadEnabled(
                from: entity,
                profileID: profileID,
                activation: activation,
                mutationLease: mutationLease
            )
        }

        let loadedContext = try authority.beginFinalization(
            extensionID: entity.id,
            profileID: profileID,
            mutationLease: mutationLease
        )
        defer { _ = authority.finish(loadedContext) }
        try await finalizer.finalize(
            loadedContext,
            activation: activation
        )
        return nil
    }

    func recover(
        entity: ExtensionEntity,
        profileID: UUID,
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws {
        runtimeAccess.ensureExtensionController(profileID)
        guard runtimeAccess.getExtensionContext(entity.id, profileID) != nil
        else {
            try await loader.restoreEnabledRuntime(
                from: entity,
                profileID: profileID,
                mutationLease: mutationLease
            )
            return
        }

        let loadedContext = try authority.beginFinalization(
            extensionID: entity.id,
            profileID: profileID,
            mutationLease: mutationLease
        )
        defer { _ = authority.finish(loadedContext) }
        try await finalizer.finalize(
            loadedContext,
            activation: .background(.enable)
        )
    }
}
