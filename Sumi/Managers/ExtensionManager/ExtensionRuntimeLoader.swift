import Foundation
import SwiftData

/// Loads one persisted extension into one profile runtime and commits the
/// manifest-derived metadata only after the exact WebKit binding is fully
/// finalized. Installation activation, retirement, and multi-profile recovery
/// are separate transactions.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeLoader {
    private enum MetadataCommit: Equatable {
        case refreshFromManifest
        case preservePersistedRecord
    }

    private let modelContext: ModelContext
    private let metadataStore: ExtensionInstallationMetadataStore
    private let installedRecords: InstalledExtensionCollection
    private let runtimeAccess: ExtensionRuntimeAccess
    private let runtimeCatalog: ExtensionRuntimeCatalog
    private let runtimeMetrics: ExtensionRuntimeMetricsAuthority
    private let authority: ExtensionLoadedContextAuthority
    private let rollback: ExtensionRuntimeRollback
    private let contextLoader: ExtensionContextLoader
    private let finalizer: ExtensionLoadedContextFinalizer
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        modelContext: ModelContext,
        metadataStore: ExtensionInstallationMetadataStore,
        installedRecords: InstalledExtensionCollection,
        runtimeAccess: ExtensionRuntimeAccess,
        runtimeCatalog: ExtensionRuntimeCatalog,
        runtimeMetrics: ExtensionRuntimeMetricsAuthority,
        authority: ExtensionLoadedContextAuthority,
        rollback: ExtensionRuntimeRollback,
        contextLoader: ExtensionContextLoader,
        finalizer: ExtensionLoadedContextFinalizer,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.modelContext = modelContext
        self.metadataStore = metadataStore
        self.installedRecords = installedRecords
        self.runtimeAccess = runtimeAccess
        self.runtimeCatalog = runtimeCatalog
        self.runtimeMetrics = runtimeMetrics
        self.authority = authority
        self.rollback = rollback
        self.contextLoader = contextLoader
        self.finalizer = finalizer
        self.diagnostics = diagnostics
    }

    func loadEnabled(
        from entity: ExtensionEntity,
        profileID: UUID? = nil,
        postLoadBackgroundWakeReason:
            ExtensionManager.ExtensionBackgroundWakeReason? = nil,
        mutationLease: ExtensionRuntimeMutationLease? = nil
    ) async throws -> InstalledExtension {
        try await loadEnabled(
            from: entity,
            profileID: profileID,
            activation: .background(postLoadBackgroundWakeReason),
            mutationLease: mutationLease
        )
    }

    func loadEnabled(
        from entity: ExtensionEntity,
        profileID: UUID? = nil,
        activation: ExtensionLoadedContextFinalizer.Activation,
        mutationLease: ExtensionRuntimeMutationLease? = nil
    ) async throws -> InstalledExtension {
        guard let refreshed = try await activate(
            entity,
            profileID: profileID,
            activation: activation,
            mutationLease: mutationLease,
            metadataCommit: .refreshFromManifest
        ) else {
            assertionFailure("Enabled runtime load must refresh its record")
            throw CancellationError()
        }
        return refreshed
    }

    /// Restores a missing context after a failed lifecycle transaction while
    /// preserving the exact metadata record already restored by that caller.
    func restoreEnabledRuntime(
        from entity: ExtensionEntity,
        profileID: UUID,
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws {
        _ = try await activate(
            entity,
            profileID: profileID,
            activation: .background(.enable),
            mutationLease: mutationLease,
            metadataCommit: .preservePersistedRecord
        )
    }

    private func activate(
        _ entity: ExtensionEntity,
        profileID: UUID?,
        activation: ExtensionLoadedContextFinalizer.Activation,
        mutationLease: ExtensionRuntimeMutationLease?,
        metadataCommit: MetadataCommit
    ) async throws -> InstalledExtension? {
        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.loadEnabledExtension"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.loadEnabledExtension",
                signpostState
            )
        }

        guard let resolvedProfileID = runtimeAccess.resolvedProfileId(
            profileID
        ) else {
            throw ExtensionError.installationFailed(
                "Extension runtime profile is unavailable"
            )
        }
        let claim = try authority.beginLoad(
            extensionID: entity.id,
            profileID: resolvedProfileID,
            mutationLease: mutationLease
        )
        defer { _ = authority.finish(claim) }

        var loadedContext: ExtensionLoadedContext?
        do {
            let sourceKind =
                WebExtensionSourceKind(rawValue: entity.sourceKindRawValue)
                    ?? .directory
            let extensionRoot = try metadataStore.extensionResourcesRoot(
                sourceKind: sourceKind,
                packagePath: entity.packagePath,
                sourceBundlePath: entity.sourceBundlePath
            )
            let manifestURL = extensionRoot.appendingPathComponent(
                "manifest.json"
            )
            trace(
                "loadEnabledExtension start extensionId=\(entity.id) "
                    + "profileId=\(resolvedProfileID.uuidString) "
                    + "packagePath=\(extensionRoot.path)"
            )
            let validationStart = CFAbsoluteTimeGetCurrent()
            let manifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: WebExtensionManifestValidationPolicy.forSourceKind(
                    sourceKind
                )
            )
            runtimeMetrics.recordManifestValidationDuration(
                CFAbsoluteTimeGetCurrent() - validationStart,
                for: entity.id
            )

            let loaded = try await contextLoader.load(
                .init(
                    extensionId: entity.id,
                    profileId: resolvedProfileID,
                    sourceKind: sourceKind,
                    sourceBundlePath: entity.sourceBundlePath,
                    packageRoot: extensionRoot,
                    manifest: manifest,
                    operation: activation.loadOperation,
                    claim: claim,
                    mutationLease: mutationLease
                )
            )
            loadedContext = loaded
            try authority.validate(loaded)

            runtimeCatalog.clearLoadError(
                extensionID: entity.id,
                profileID: resolvedProfileID
            )
            try await finalizer.finalize(loaded, activation: activation)
            try authority.validate(loaded)

            guard metadataCommit == .refreshFromManifest else {
                runtimeCatalog.recordManifest(manifest, for: entity.id)
                try finalizer.settlePublication(loaded)
                return nil
            }

            let refreshed = try metadataStore.refreshedRecord(
                for: entity,
                manifest: manifest
            )
            try authority.validate(loaded)
            metadataStore.update(entity, from: refreshed)
            try modelContext.save()
            runtimeCatalog.recordManifest(manifest, for: entity.id)
            installedRecords.upsert(refreshed)
            try finalizer.settlePublication(loaded)
            return refreshed
        } catch {
            if let loadedContext {
                let rollbackResult = rollback.rollBack(loadedContext)
                if rollbackResult.externalStateDisposition != .rollbackAllowed {
                    throw ExtensionRuntimeTransactionFailure(
                        operationError: error,
                        rollback: rollbackResult
                    )
                }
            }
            if !(error is CancellationError), authority.isCurrent(claim) {
                runtimeCatalog.recordLoadError(
                    error,
                    extensionID: entity.id,
                    profileID: resolvedProfileID
                )
            }
            throw error
        }
    }

    private func trace(_ message: @autoclosure () -> String) {
        guard ExtensionManager.isWebKitRuntimeTraceEnabled else { return }
        diagnostics.trace(message())
    }
}
