import Foundation

/// Coordinates one prepared package, one installed-record transaction and one
/// profile-scoped WebKit activation. Source identity, failure policy and each
/// side-effect transaction remain independent collaborators.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationService {
    private let metadataStore: ExtensionInstallationMetadataStore
    private let recordTransaction: ExtensionInstallationRecordTransaction
    private let runtimeActivation: ExtensionInstallationRuntimeActivation
    private let runtimeReplacement: ExtensionInstallationRuntimeReplacement
    private let failureSettlement: ExtensionInstallationFailureSettlement
    private let mutationRegistry: ExtensionRuntimeMutationRegistry
    private let loadRegistry: ExtensionContextLoadRegistry
    private let sourceAdmission: ExtensionInstallationAdmission
    private let activePackageGenerations: ExtensionPackageGenerationRegistry
    private let packageMaintenance: ExtensionPackageMaintenance
    private let packageFileExecutor: ExtensionPackageFileExecutor
    private let requestRuntimeForInstallation: @MainActor () -> Void
    private let removeStoredData: @MainActor (
        String, WebExtensionStorageCleanupPlanner.CleanupMode
    ) async -> Void
    private let hasStoredDataCandidate: @MainActor (String) -> Bool
    private let traceStoreLifecycle: @MainActor (
        String, String, [String: Any]?
    ) -> Void
    private let ensureStorageDirectory: @MainActor (String) -> Void
    #if DEBUG
        private var debugBeforePersist: (@MainActor ()
            -> ((InstalledExtension) throws -> Void)?)?
    #endif
    private let emitTrace: @MainActor (String) -> Void

    init(
        metadataStore: ExtensionInstallationMetadataStore,
        recordTransaction: ExtensionInstallationRecordTransaction,
        runtimeActivation: ExtensionInstallationRuntimeActivation,
        runtimeReplacement: ExtensionInstallationRuntimeReplacement,
        failureSettlement: ExtensionInstallationFailureSettlement,
        mutationRegistry: ExtensionRuntimeMutationRegistry,
        loadRegistry: ExtensionContextLoadRegistry,
        sourceAdmission: ExtensionInstallationAdmission,
        activePackageGenerations: ExtensionPackageGenerationRegistry,
        packageMaintenance: ExtensionPackageMaintenance,
        packageFileExecutor: ExtensionPackageFileExecutor = .init(),
        requestRuntimeForInstallation: @escaping @MainActor () -> Void,
        removeStoredData: @escaping @MainActor (
            String, WebExtensionStorageCleanupPlanner.CleanupMode
        ) async -> Void,
        hasStoredDataCandidate: @escaping @MainActor (String) -> Bool,
        traceStoreLifecycle: @escaping @MainActor (
            String, String, [String: Any]?
        ) -> Void,
        ensureStorageDirectory: @escaping @MainActor (String) -> Void,
        emitTrace: @escaping @MainActor (String) -> Void
    ) {
        self.metadataStore = metadataStore
        self.recordTransaction = recordTransaction
        self.runtimeActivation = runtimeActivation
        self.runtimeReplacement = runtimeReplacement
        self.failureSettlement = failureSettlement
        self.mutationRegistry = mutationRegistry
        self.loadRegistry = loadRegistry
        self.sourceAdmission = sourceAdmission
        self.activePackageGenerations = activePackageGenerations
        self.packageMaintenance = packageMaintenance
        self.packageFileExecutor = packageFileExecutor
        self.requestRuntimeForInstallation = requestRuntimeForInstallation
        self.removeStoredData = removeStoredData
        self.hasStoredDataCandidate = hasStoredDataCandidate
        self.traceStoreLifecycle = traceStoreLifecycle
        self.ensureStorageDirectory = ensureStorageDirectory
        self.emitTrace = emitTrace
    }

    #if DEBUG
        func installDebugBeforePersist(
            _ provider: @escaping @MainActor ()
                -> ((InstalledExtension) throws -> Void)?
        ) {
            debugBeforePersist = provider
        }
    #endif

    func install(
        from sourceURL: URL,
        completionHandler: @escaping (
            Result<InstalledExtension, ExtensionError>
        ) -> Void
    ) {
        Task {
            do {
                deliver(
                    .success(try await install(from: sourceURL)),
                    to: completionHandler
                )
            } catch let error as ExtensionError {
                deliver(.failure(error), to: completionHandler)
            } catch {
                deliver(
                    .failure(.installationFailed(error.localizedDescription)),
                    to: completionHandler
                )
            }
        }
    }

    func install(
        from sourceURL: URL,
        enableOnInstall: Bool = true
    ) async throws -> InstalledExtension {
        let source = try ExtensionInstallSourceResolver.resolve(at: sourceURL)
        guard let sourceClaim = sourceAdmission.begin(
            sourceBundleURL: source.sourceBundlePath
        ) else {
            throw ExtensionError.installationFailed(
                "Another installation is already using this source package"
            )
        }
        defer { _ = sourceAdmission.finish(sourceClaim) }

        if enableOnInstall {
            requestRuntimeForInstallation()
        }

        let package = try await ExtensionInstallationPackage.prepare(
            source: source,
            extensionsDirectory: ExtensionPathSafety.extensionsDirectory(),
            activeGenerations: activePackageGenerations,
            fileExecutor: packageFileExecutor
        )
        let identity: ExtensionInstallationIdentityResolver.Resolution
        do {
            identity = try resolveIdentity(
                source: source,
                package: package
            )
        } catch {
            throw await compensateUnusedPackage(
                package,
                originalError: error
            )
        }

        let existingEntity: ExtensionEntity?
        do {
            existingEntity = if let existingExtensionID =
                identity.existingExtensionID {
                try metadataStore.extensionEntity(for: existingExtensionID)
            } else {
                nil
            }
        } catch {
            throw await compensateUnusedPackage(
                package,
                originalError: error
            )
        }

        guard let mutationLease = mutationRegistry.begin(
            extensionID: identity.extensionID,
            operation: .install
        ) else {
            throw await compensateUnusedPackage(
                package,
                originalError: ExtensionError.installationFailed(
                    "Another lifecycle operation is already running for this extension"
                )
            )
        }
        defer { _ = mutationRegistry.finish(mutationLease) }
        loadRegistry.invalidate(extensionId: identity.extensionID)

        let recordSnapshot = ExtensionInstallationRecordTransaction.Snapshot(
            extensionID: identity.extensionID,
            originalRecord: existingEntity.flatMap(InstalledExtension.init(from:))
        )
        var previousRuntime:
            ExtensionInstallationRuntimeReplacement.PreviousRuntime?
        var activation: ExtensionInstallationRuntimeActivation.Transaction?
        var candidateRecord: InstalledExtension?

        do {
            if let existingEntity {
                previousRuntime = try await runtimeReplacement.retire(
                    existingEntity,
                    mutationLease: mutationLease
                )
            } else if package.ownership == .copiedDirectory {
                try await prepareFreshDirectoryStorage(
                    extensionID: identity.extensionID,
                    manifest: package.manifest,
                    mutationLease: mutationLease
                )
            }

            let materialized = try await package.materialize(
                extensionID: identity.extensionID
            )
            let record = try metadataStore.makeInstalledRecord(
                extensionId: identity.extensionID,
                manifest: materialized.manifest,
                extensionRoot: materialized.root,
                isEnabled: enableOnInstall,
                sourceKind: source.sourceKind,
                sourceBundlePath: source.sourceBundlePath.path,
                sourceFingerprintURL: source.sourceFingerprintURL,
                manifestRootFingerprint: materialized.manifestFingerprint,
                existingEntity: existingEntity
            )
            candidateRecord = record

            if enableOnInstall {
                let loaded = try await runtimeActivation.load(
                    extensionID: identity.extensionID,
                    sourceKind: source.sourceKind,
                    sourceBundlePath: source.sourceBundlePath.path,
                    packageRoot: materialized.root,
                    manifest: materialized.manifest,
                    operation: package.runtimeOperation,
                    mutationLease: mutationLease
                )
                activation = loaded
                try await runtimeActivation.finalize(
                    loaded,
                    operation: package.runtimeOperation
                )
            } else {
                ensureStorageDirectory(identity.extensionID)
            }

            #if DEBUG
                if let beforePersist = debugBeforePersist?() {
                    try beforePersist(record)
                }
            #endif
            if let activation {
                try runtimeActivation.validate(activation)
            }
            try validate(mutationLease)
            try recordTransaction.commitCandidate(
                record,
                replacing: recordSnapshot
            )
            if let activation {
                runtimeActivation.settlePublication(activation)
            }
            await package.commit()
            if let activation {
                runtimeActivation.finish(activation)
            }
            activation = nil
            retireSupersededPackage(from: existingEntity)
            return record
        } catch {
            let rollbackRuntimeActivation: (@MainActor @Sendable () ->
                ExtensionLoadedContextAuthority.RollbackResult)?
            if let activation {
                rollbackRuntimeActivation = { @MainActor [runtimeActivation] in
                    runtimeActivation.rollback(activation)
                }
            } else {
                rollbackRuntimeActivation = nil
            }
            throw await failureSettlement.settle(
                .init(
                    error: error,
                    package: package,
                    recordSnapshot: recordSnapshot,
                    candidateRecord: candidateRecord,
                    previousRuntime: previousRuntime,
                    rollbackRuntimeActivation: rollbackRuntimeActivation,
                    mutationLease: mutationLease
                )
            )
        }
    }

    private func resolveIdentity(
        source: ExtensionInstallSourceResolver.ResolvedInstallSource,
        package: ExtensionInstallationPackage
    ) throws -> ExtensionInstallationIdentityResolver.Resolution {
        try ExtensionInstallationIdentityResolver.resolve(
            .init(
                sourceBundleURL: source.sourceBundlePath,
                declaredExtensionID:
                    package.preferredDeclaredExtensionID
                    ?? geckoExtensionID(from: package.manifest),
                sourceKind: source.sourceKind,
                safariRuntimeIdentity:
                    SafariWebExtensionRuntimeIdentity.composedIdentifier(
                        sourceKind: source.sourceKind,
                        sourceBundlePath: source.sourceBundlePath.path
                    ),
                freshExtensionID: UUID().uuidString,
                persistedIdentities:
                    try metadataStore.persistedInstallationIdentities()
            )
        )
    }

    private func prepareFreshDirectoryStorage(
        extensionID: String,
        manifest: [String: Any],
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws {
        guard hasStoredDataCandidate(extensionID) else {
            if RuntimeDiagnostics.isVerboseEnabled {
                trace(
                    "Skipped WebExtension data cleanup for \(extensionID): no stored data candidate (fresh install path)"
                )
            }
            return
        }
        traceStoreLifecycle(
            "before-install-cleanup",
            extensionID,
            manifest
        )
        await removeStoredData(
            extensionID,
            .preserveDirectoryForImmediateRuntimeLoad
        )
        try validate(mutationLease)
        traceStoreLifecycle(
            "after-install-cleanup",
            extensionID,
            manifest
        )
    }

    private func compensateUnusedPackage(
        _ package: ExtensionInstallationPackage,
        originalError: any Error
    ) async -> any Error {
        do {
            try await package.rollback()
            return originalError
        } catch {
            return ExtensionError.installationFailed(
                "Installation preparation failed: "
                    + originalError.localizedDescription
                    + ". Package cleanup also failed: "
                    + error.localizedDescription
            )
        }
    }

    private func supersededPackageRoot(
        from entity: ExtensionEntity?
    ) -> URL? {
        guard let entity,
              WebExtensionSourceKind(rawValue: entity.sourceKindRawValue)
                == .directory else {
            return nil
        }
        return URL(fileURLWithPath: entity.packagePath, isDirectory: true)
    }

    private func retireSupersededPackage(from entity: ExtensionEntity?) {
        guard let packageRoot = supersededPackageRoot(from: entity),
              FileManager.default.fileExists(atPath: packageRoot.path) else {
            return
        }
        do {
            let quarantined = try packageMaintenance.quarantinePackage(
                packageRoot
            )
            packageMaintenance.deleteQuarantinedPackages([quarantined])
        } catch {
            trace(
                "Committed extension replacement but left superseded package for startup cleanup: \(error.localizedDescription)"
            )
        }
    }

    private func validate(_ lease: ExtensionRuntimeMutationLease) throws {
        guard mutationRegistry.isCurrent(lease) else {
            throw CancellationError()
        }
    }

    private func geckoExtensionID(from manifest: [String: Any]) -> String? {
        guard let browserSettings =
                manifest["browser_specific_settings"] as? [String: Any],
              let gecko = browserSettings["gecko"] as? [String: Any]
        else {
            return nil
        }
        return gecko["id"] as? String
    }

    private func deliver(
        _ result: Result<InstalledExtension, ExtensionError>,
        to completionHandler: @escaping (
            Result<InstalledExtension, ExtensionError>
        ) -> Void
    ) {
        Task { @MainActor in
            await Task.yield()
            completionHandler(result)
        }
    }

    private func trace(_ message: @autoclosure () -> String) {
        emitTrace(message())
    }
}
