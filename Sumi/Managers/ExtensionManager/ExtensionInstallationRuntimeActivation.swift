import Foundation

/// Holds the exact load claim across install-time WebKit activation and the
/// later persistence commit. A caller can therefore compensate any failure
/// with the same binding receipt instead of reconstructing mutable state.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationRuntimeActivation {
    enum Operation {
        case directory
        case safariAppExtension

        var contextLoadOperation: ExtensionRuntimeContextLoader.Operation {
            switch self {
            case .directory: .install
            case .safariAppExtension: .safariEnable
            }
        }

        var activationOperation: ExtensionInstallRuntimeActivator.Operation {
            switch self {
            case .directory: .install
            case .safariAppExtension: .safariEnable
            }
        }
    }

    struct Transaction {
        fileprivate let loadedContext:
            ExtensionRuntimeContextLoader.LoadedContext
    }

    private let runtimeAccess: ExtensionRuntimeAccess
    private let authority: ExtensionLoadedContextAuthority
    private let rollback: ExtensionRuntimeRollback
    private let contextLoader: ExtensionRuntimeContextLoader
    private let activation: ExtensionInstallRuntimeActivator

    init(
        runtimeAccess: ExtensionRuntimeAccess,
        authority: ExtensionLoadedContextAuthority,
        rollback: ExtensionRuntimeRollback,
        contextLoader: ExtensionRuntimeContextLoader,
        activation: ExtensionInstallRuntimeActivator
    ) {
        self.runtimeAccess = runtimeAccess
        self.authority = authority
        self.rollback = rollback
        self.contextLoader = contextLoader
        self.activation = activation
    }

    func load(
        extensionID: String,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        packageRoot: URL,
        manifest: [String: Any],
        operation: Operation,
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws -> Transaction {
        guard let profileID = runtimeAccess.resolvedProfileId(nil) else {
            throw ExtensionError.installationFailed(
                "Extension runtime profile is unavailable"
            )
        }
        let claim = try authority.beginLoad(
            extensionID: extensionID,
            profileID: profileID,
            mutationLease: mutationLease
        )
        do {
            let loadedContext = try await contextLoader.load(
                .init(
                    extensionId: extensionID,
                    profileId: profileID,
                    sourceKind: sourceKind,
                    sourceBundlePath: sourceBundlePath,
                    packageRoot: packageRoot,
                    manifest: manifest,
                    operation: operation.contextLoadOperation,
                    claim: claim,
                    mutationLease: mutationLease
                )
            )
            try authority.validate(loadedContext)
            return Transaction(loadedContext: loadedContext)
        } catch {
            _ = authority.finish(claim)
            throw error
        }
    }

    func finalize(
        _ transaction: Transaction,
        operation: Operation
    ) async throws {
        try authority.validate(transaction.loadedContext)
        try await activation.activate(
            .init(
                loadedContext: transaction.loadedContext,
                installedExtensionId:
                    transaction.loadedContext.bindingReceipt.key.extensionId,
                operation: operation.activationOperation
            )
        )
        try authority.validate(transaction.loadedContext)
    }

    func validate(_ transaction: Transaction) throws {
        try authority.validate(transaction.loadedContext)
    }

    func finish(_ transaction: Transaction) {
        _ = authority.finish(transaction.loadedContext)
    }

    func rollback(
        _ transaction: Transaction
    ) -> ExtensionLoadedContextAuthority.RollbackResult {
        let result = rollback.rollBack(transaction.loadedContext)
        finish(transaction)
        return result
    }
}
