import Foundation
import SwiftData

/// Coordinates extension installation across a reversible package transaction,
/// persisted metadata, and profile-scoped WebKit activation.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationService {
    struct Environment {
        let modelContext: ModelContext
        let metadataStore: ExtensionInstallationMetadataStore
        let installedRecords: InstalledExtensionCollection
        let runtimeActivation: ExtensionInstallationRuntimeActivation
        let runtimeRecovery: ExtensionRuntimeRecovery
        let runtimeRetirement: ExtensionRuntimeRetirement
        let mutationRegistry: ExtensionRuntimeMutationRegistry
        let loadRegistry: ExtensionContextLoadRegistry
        let isExtensionSupportAvailable: @MainActor () -> Bool
        let requestRuntime: @MainActor (
            ExtensionManager.ExtensionRuntimeRequestReason, Bool
        ) async -> Void
        let removeStoredData: @MainActor (
            String, ExtensionManager.WebExtensionStorageCleanupMode
        ) async -> Void
        let hasStoredDataCandidate: @MainActor (String) -> Bool
        let traceStoreLifecycle: @MainActor (String, String, [String: Any]?) -> Void
        let ensureStorageDirectory: @MainActor (String) -> Void
        let debugBeforePersist: @MainActor () -> ((InstalledExtension) throws -> Void)?
        let trace: @MainActor (String) -> Void
    }

    private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    func install(
        from sourceURL: URL,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        guard environment.isExtensionSupportAvailable() else {
            deliver(.failure(.unsupportedOS), to: completionHandler)
            return
        }

        Task {
            do {
                deliver(.success(try await install(from: sourceURL)), to: completionHandler)
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
        if enableOnInstall {
            await environment.requestRuntime(.install, true)
        }

        let source = try ExtensionInstallSourceResolver.resolve(at: sourceURL)
        if source.sourceKind == .safariAppExtension {
            return try await installSafariAppExtension(
                source,
                enableOnInstall: enableOnInstall
            )
        }
        return try await installDirectoryExtension(
            source,
            enableOnInstall: enableOnInstall
        )
    }

    private func installDirectoryExtension(
        _ source: ExtensionInstallSourceResolver.ResolvedInstallSource,
        enableOnInstall: Bool
    ) async throws -> InstalledExtension {
        let transaction = ExtensionPackageInstallTransaction(
            extensionsDirectory: ExtensionUtils.extensionsDirectory()
        )
        var extensionID: String?
        var existingEntity: ExtensionEntity?
        var originalRecord: InstalledExtension?
        var shouldRestoreRuntime = false
        var didAttemptPersistence = false
        var runtimeActivation:
            ExtensionInstallationRuntimeActivation.Transaction?
        var mutationLease: ExtensionRuntimeMutationLease?
        var previousRuntimeProfileIDs = Set<UUID>()
        var didRetirePreviousRuntime = false
        var candidateRecord: InstalledExtension?

        do {
            try transaction.stage(resourcesAt: source.resourcesURL)
            let manifestPolicy = WebExtensionManifestValidationPolicy.forSourceKind(
                source.sourceKind
            )
            let stagedManifest = try ExtensionUtils.validateManifest(
                at: transaction.stagedPackageRoot.appendingPathComponent("manifest.json"),
                policy: manifestPolicy
            )
            try ExtensionInstallSourceResolver.validateMV3Requirements(
                manifest: stagedManifest,
                baseURL: transaction.stagedPackageRoot
            )

            let entities = try environment.modelContext.fetch(
                FetchDescriptor<ExtensionEntity>()
            )
            let sourceRecord = entities.first {
                $0.sourceBundlePath == source.sourceBundlePath.path
            }
            let resolvedID = try resolvedExtensionID(
                manifest: stagedManifest,
                existingEntity: sourceRecord
            )
            let lease = try beginInstallationMutation(extensionID: resolvedID)
            mutationLease = lease
            environment.loadRegistry.invalidate(extensionId: resolvedID)
            extensionID = resolvedID
            existingEntity = try environment.metadataStore.extensionEntity(for: resolvedID)
            originalRecord = existingEntity.flatMap(InstalledExtension.init(from:))
            shouldRestoreRuntime = existingEntity?.isEnabled == true

            if let existingEntity {
                let retirement = retireRuntime(
                    extensionID: existingEntity.id,
                    cause: .packageReplacement,
                    mutationLease: lease
                )
                previousRuntimeProfileIDs = retirement.initialProfileIDs
                try await requireCompletedReplacementRetirement(
                    retirement,
                    existingEntity: existingEntity,
                    mutationLease: lease
                )
                didRetirePreviousRuntime = true
            } else if environment.hasStoredDataCandidate(resolvedID) {
                environment.traceStoreLifecycle(
                    "before-install-cleanup",
                    resolvedID,
                    stagedManifest
                )
                await environment.removeStoredData(
                    resolvedID,
                    .preserveDirectoryForImmediateRuntimeLoad
                )
                try validate(lease)
                environment.traceStoreLifecycle(
                    "after-install-cleanup",
                    resolvedID,
                    stagedManifest
                )
            } else if RuntimeDiagnostics.isVerboseEnabled {
                trace(
                    "Skipped WebExtension data cleanup for \(resolvedID): no stored data candidate (fresh install path)"
                )
            }

            let installedRoot = try transaction.installStagedPackage(
                extensionID: resolvedID
            )
            let finalManifest = try ExtensionUtils.validateManifest(
                at: installedRoot.appendingPathComponent("manifest.json"),
                policy: manifestPolicy
            )
            let record = try environment.metadataStore.makeInstalledRecord(
                extensionId: resolvedID,
                manifest: finalManifest,
                extensionRoot: installedRoot,
                isEnabled: enableOnInstall,
                sourceKind: source.sourceKind,
                sourceBundlePath: source.sourceBundlePath.path,
                sourceFingerprintURL: source.sourceFingerprintURL,
                existingEntity: existingEntity
            )
            candidateRecord = record

            if enableOnInstall {
                let activation = try await environment.runtimeActivation
                    .load(
                    extensionID: resolvedID,
                    sourceKind: source.sourceKind,
                    sourceBundlePath: source.sourceBundlePath.path,
                    packageRoot: installedRoot,
                    manifest: finalManifest,
                    operation: .directory,
                    mutationLease: lease
                )
                runtimeActivation = activation
                try await environment.runtimeActivation.finalize(
                    activation,
                    operation: .directory
                )
            } else {
                environment.ensureStorageDirectory(resolvedID)
            }

            if let beforePersist = environment.debugBeforePersist() {
                try beforePersist(record)
            }
            if let runtimeActivation {
                try environment.runtimeActivation.validate(runtimeActivation)
            }
            try validate(lease)
            didAttemptPersistence = true
            try environment.metadataStore.persist(record: record)
            publish(record)
            transaction.commit()
            if let runtimeActivation {
                environment.runtimeActivation.finish(runtimeActivation)
            }
            runtimeActivation = nil
            _ = environment.mutationRegistry.finish(lease)
            mutationLease = nil
            return record
        } catch {
            defer {
                if let mutationLease {
                    _ = environment.mutationRegistry.finish(mutationLease)
                }
            }
            var externalStateDisposition =
                (error as? ExtensionRuntimeTransactionFailure)?
                    .rollback.externalStateDisposition
                    ?? .rollbackAllowed
            var recoveryFailures: [String] = []
            if let runtimeActivation {
                externalStateDisposition = environment
                    .runtimeActivation
                    .rollback(runtimeActivation)
                    .externalStateDisposition
            }
            switch externalStateDisposition {
            case .rollbackAllowed:
                transaction.rollback()
                if didAttemptPersistence, let extensionID {
                    do {
                        try rollbackPersistedRecord(
                            extensionID: extensionID,
                            originalRecord: originalRecord
                        )
                    } catch {
                        recoveryFailures.append(
                            "metadata rollback failed: \(error.localizedDescription)"
                        )
                    }
                }
                if didRetirePreviousRuntime,
                   shouldRestoreRuntime,
                   let existingEntity,
                   let mutationLease {
                    do {
                        try await environment.runtimeRecovery.recoverEnabledRuntime(
                            from: existingEntity,
                            profileIDs: previousRuntimeProfileIDs,
                            mutationLease: mutationLease
                        )
                    } catch {
                        recoveryFailures.append(
                            "previous runtime recovery failed: \(error.localizedDescription)"
                        )
                    }
                }
            case .preserveForExactRuntime:
                if let candidateRecord {
                    do {
                        try environment.metadataStore.persist(
                            record: candidateRecord
                        )
                    } catch {
                        recoveryFailures.append(
                            "live-runtime metadata commit failed: "
                                + error.localizedDescription
                        )
                    }
                    publish(candidateRecord)
                }
                transaction.commit()
                throw ExtensionError.installationFailed(
                    "Installation failed after the new WebKit runtime became authoritative; its installed package and candidate metadata were preserved"
                        + (recoveryFailures.isEmpty
                            ? ""
                            : ". Recovery issues: "
                                + recoveryFailures.joined(separator: "; "))
                        + ". Original error: \(error.localizedDescription)"
                )
            case .preserveForReplacement,
                 .preserveForActiveBinding,
                 .preserveForCompetingTransaction,
                 .preserveUntilSharedCleanup:
                transaction.commit()
                throw ExtensionError.installationFailed(
                    "Installation failed after another runtime authority acquired the extension; installed package bytes were preserved without overwriting its metadata"
                        + ". Original error: \(error.localizedDescription)"
                )
            }
            if recoveryFailures.isEmpty == false {
                throw ExtensionError.installationFailed(
                    "Installation failed and recovery was incomplete: "
                        + recoveryFailures.joined(separator: "; ")
                        + ". Original error: \(error.localizedDescription)"
                )
            }
            throw error
        }
    }

    private func installSafariAppExtension(
        _ source: ExtensionInstallSourceResolver.ResolvedInstallSource,
        enableOnInstall: Bool
    ) async throws -> InstalledExtension {
        guard let appexBundleURL = source.appexBundleURL,
              let bundle = Bundle(url: appexBundleURL) else {
            throw ExtensionError.installationFailed(
                "Installed Safari app extension bundle is unavailable"
            )
        }

        let manifestPolicy = WebExtensionManifestValidationPolicy.forSourceKind(
            source.sourceKind
        )
        let manifest = try ExtensionUtils.validateManifest(
            at: source.resourcesURL.appendingPathComponent("manifest.json"),
            policy: manifestPolicy
        )
        try ExtensionInstallSourceResolver.validateMV3Requirements(
            manifest: manifest,
            baseURL: source.resourcesURL
        )
        let entities = try environment.modelContext.fetch(FetchDescriptor<ExtensionEntity>())
        let sourceRecord = entities.first {
            URL(fileURLWithPath: $0.sourceBundlePath, isDirectory: true)
                .standardizedFileURL.path == source.sourceBundlePath.standardizedFileURL.path
        }
        let extensionID = try resolvedExtensionID(
            manifest: manifest,
            existingEntity: sourceRecord,
            preferredBundleIdentifier: bundle.bundleIdentifier
        )
        let existingEntity: ExtensionEntity?
        if let sourceRecord {
            existingEntity = sourceRecord
        } else {
            existingEntity = try environment.metadataStore.extensionEntity(
                for: extensionID
            )
        }
        let originalRecord = existingEntity.flatMap(InstalledExtension.init(from:))
        let shouldRestoreRuntime = existingEntity?.isEnabled == true
        var didAttemptPersistence = false
        var runtimeActivation:
            ExtensionInstallationRuntimeActivation.Transaction?
        var previousRuntimeProfileIDs = Set<UUID>()
        var didRetirePreviousRuntime = false
        var candidateRecord: InstalledExtension?
        let mutationLease = try beginInstallationMutation(
            extensionID: extensionID
        )
        environment.loadRegistry.invalidate(extensionId: extensionID)

        do {
            if let existingEntity {
                let retirement = retireRuntime(
                    extensionID: existingEntity.id,
                    cause: .packageReplacement,
                    mutationLease: mutationLease
                )
                previousRuntimeProfileIDs = retirement.initialProfileIDs
                try await requireCompletedReplacementRetirement(
                    retirement,
                    existingEntity: existingEntity,
                    mutationLease: mutationLease
                )
                didRetirePreviousRuntime = true
            }
            let record = try environment.metadataStore.makeInstalledRecord(
                extensionId: extensionID,
                manifest: manifest,
                extensionRoot: source.resourcesURL,
                isEnabled: enableOnInstall,
                sourceKind: source.sourceKind,
                sourceBundlePath: source.sourceBundlePath.path,
                sourceFingerprintURL: source.sourceFingerprintURL,
                existingEntity: existingEntity
            )
            candidateRecord = record

            if enableOnInstall {
                let activation = try await environment.runtimeActivation
                    .load(
                    extensionID: extensionID,
                    sourceKind: source.sourceKind,
                    sourceBundlePath: source.sourceBundlePath.path,
                    packageRoot: source.resourcesURL,
                    manifest: manifest,
                    operation: .safariAppExtension,
                    mutationLease: mutationLease
                )
                runtimeActivation = activation
                try await environment.runtimeActivation.finalize(
                    activation,
                    operation: .safariAppExtension
                )
            } else {
                environment.ensureStorageDirectory(extensionID)
            }

            if let beforePersist = environment.debugBeforePersist() {
                try beforePersist(record)
            }
            if let runtimeActivation {
                try environment.runtimeActivation.validate(runtimeActivation)
            }
            try validate(mutationLease)
            didAttemptPersistence = true
            try environment.metadataStore.persist(record: record)
            publish(record)
            if let runtimeActivation {
                environment.runtimeActivation.finish(runtimeActivation)
            }
            runtimeActivation = nil
            _ = environment.mutationRegistry.finish(mutationLease)
            return record
        } catch {
            defer {
                _ = environment.mutationRegistry.finish(mutationLease)
            }
            var externalStateDisposition =
                (error as? ExtensionRuntimeTransactionFailure)?
                    .rollback.externalStateDisposition
                    ?? .rollbackAllowed
            var recoveryFailures: [String] = []
            if let runtimeActivation {
                externalStateDisposition = environment
                    .runtimeActivation
                    .rollback(runtimeActivation)
                    .externalStateDisposition
            }
            switch externalStateDisposition {
            case .rollbackAllowed:
                if didAttemptPersistence {
                    do {
                        try rollbackPersistedRecord(
                            extensionID: extensionID,
                            originalRecord: originalRecord
                        )
                    } catch {
                        recoveryFailures.append(
                            "metadata rollback failed: \(error.localizedDescription)"
                        )
                    }
                }
                if didRetirePreviousRuntime,
                   shouldRestoreRuntime,
                   let existingEntity {
                    do {
                        try await environment.runtimeRecovery.recoverEnabledRuntime(
                            from: existingEntity,
                            profileIDs: previousRuntimeProfileIDs,
                            mutationLease: mutationLease
                        )
                    } catch {
                        recoveryFailures.append(
                            "previous runtime recovery failed: \(error.localizedDescription)"
                        )
                    }
                }
            case .preserveForExactRuntime:
                if let candidateRecord {
                    do {
                        try environment.metadataStore.persist(
                            record: candidateRecord
                        )
                    } catch {
                        recoveryFailures.append(
                            "live-runtime metadata commit failed: "
                                + error.localizedDescription
                        )
                    }
                    publish(candidateRecord)
                }
                throw ExtensionError.installationFailed(
                    "Safari extension activation failed after the new WebKit runtime became authoritative; candidate metadata was preserved"
                        + (recoveryFailures.isEmpty
                            ? ""
                            : ". Recovery issues: "
                                + recoveryFailures.joined(separator: "; "))
                        + ". Original error: \(error.localizedDescription)"
                )
            case .preserveForReplacement,
                 .preserveForActiveBinding,
                 .preserveForCompetingTransaction,
                 .preserveUntilSharedCleanup:
                throw ExtensionError.installationFailed(
                    "Safari extension activation failed after another runtime authority acquired the extension; its metadata was left untouched"
                        + ". Original error: \(error.localizedDescription)"
                )
            }
            if recoveryFailures.isEmpty == false {
                throw ExtensionError.installationFailed(
                    "Safari extension activation failed and recovery was incomplete: "
                        + recoveryFailures.joined(separator: "; ")
                        + ". Original error: \(error.localizedDescription)"
                )
            }
            throw error
        }
    }

    private func resolvedExtensionID(
        manifest: [String: Any],
        existingEntity: ExtensionEntity?,
        preferredBundleIdentifier: String? = nil
    ) throws -> String {
        let candidate: String
        if let existingEntity {
            candidate = existingEntity.id
        } else if let preferredBundleIdentifier, preferredBundleIdentifier.isEmpty == false {
            candidate = preferredBundleIdentifier
        } else if let geckoID = geckoExtensionID(from: manifest) {
            candidate = geckoID
        } else {
            candidate = UUID().uuidString
        }
        return try ExtensionUtils.validateExtensionIDPathComponent(candidate)
    }

    private func retireRuntime(
        extensionID: String,
        cause: ExtensionScopedRuntimeRetirement.Cause,
        mutationLease: ExtensionRuntimeMutationLease
    ) -> ExtensionScopedRuntimeRetirement.Result {
        environment.runtimeRetirement.retire(
            extensionID: extensionID,
            cause: cause,
            mutationLease: mutationLease
        )
    }

    private func requireCompletedReplacementRetirement(
        _ result: ExtensionScopedRuntimeRetirement.Result,
        existingEntity: ExtensionEntity,
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws {
        guard result.completed else {
            guard result.completionStatus == .contextsRemaining else {
                throw CancellationError()
            }
            do {
                try await environment.runtimeRecovery.recoverEnabledRuntime(
                    from: existingEntity,
                    profileIDs: result.initialProfileIDs,
                    mutationLease: mutationLease
                )
            } catch {
                throw ExtensionError.installationFailed(
                    "Package replacement retirement was partial and runtime recovery failed: \(error.localizedDescription)"
                )
            }
            throw ExtensionError.installationFailed(
                "Extension runtime could not be unloaded for profiles: "
                    + result.remainingProfileIDs.map(\.uuidString).sorted()
                    .joined(separator: ", ")
            )
        }
    }

    private func beginInstallationMutation(
        extensionID: String
    ) throws -> ExtensionRuntimeMutationLease {
        guard let lease = environment.mutationRegistry.begin(
            extensionID: extensionID,
            operation: .install
        ) else {
            throw ExtensionError.installationFailed(
                "Another lifecycle operation is already running for this extension"
            )
        }
        return lease
    }

    private func validate(_ lease: ExtensionRuntimeMutationLease) throws {
        guard environment.mutationRegistry.isCurrent(lease) else {
            throw CancellationError()
        }
    }

    private func geckoExtensionID(from manifest: [String: Any]) -> String? {
        guard let browserSettings = manifest["browser_specific_settings"] as? [String: Any],
              let gecko = browserSettings["gecko"] as? [String: Any] else {
            return nil
        }
        return gecko["id"] as? String
    }

    private func rollbackPersistedRecord(
        extensionID: String,
        originalRecord: InstalledExtension?
    ) throws {
        if let entity = try environment.metadataStore.extensionEntity(for: extensionID) {
            if let originalRecord {
                environment.metadataStore.update(entity, from: originalRecord)
            } else {
                environment.modelContext.delete(entity)
            }
        } else if let originalRecord {
            environment.modelContext.insert(ExtensionEntity(record: originalRecord))
        }
        try environment.modelContext.save()
    }

    private func publish(_ record: InstalledExtension) {
        environment.installedRecords.upsert(record)
    }

    private func deliver(
        _ result: Result<InstalledExtension, ExtensionError>,
        to completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        Task { @MainActor in
            await Task.yield()
            completionHandler(result)
        }
    }

    private func trace(_ message: @autoclosure () -> String) {
        guard ExtensionManager.isWebKitRuntimeTraceEnabled else { return }
        environment.trace(message())
    }
}

@available(macOS 15.5, *)
extension ExtensionInstallationService.Environment {
    @MainActor
    static func makeLive(manager: ExtensionManager) -> Self {
        Self(
            modelContext: manager.context,
            metadataStore: manager.installationMetadataStore,
            installedRecords: manager.installedExtensionCollection,
            runtimeActivation: manager.installationRuntimeActivation,
            runtimeRecovery: manager.runtimeRecovery,
            runtimeRetirement: manager.runtimeRetirement,
            mutationRegistry: manager.runtimeMutationRegistry,
            loadRegistry: manager.contextLoadRegistry,
            isExtensionSupportAvailable: { [weak manager] in
                manager?.isExtensionSupportAvailable ?? false
            },
            requestRuntime: { [weak manager] reason, allowWithoutEnabled in
                guard let manager else { return }
                _ = await manager.runtimeLifecycleOwner.requestExtensionRuntimeAndWait(
                    reason: reason,
                    allowWithoutEnabledExtensions: allowWithoutEnabled
                )
            },
            removeStoredData: { [weak manager] extensionID, mode in
                await manager?.removeStoredWebExtensionData(for: extensionID, mode: mode)
            },
            hasStoredDataCandidate: { [weak manager] extensionID in
                manager?.hasStoredWebExtensionDataCandidate(for: extensionID) ?? false
            },
            traceStoreLifecycle: { [weak manager] phase, extensionID, manifest in
                manager?.traceWebExtensionStoreLifecycle(
                    phase: phase,
                    extensionId: extensionID,
                    manifest: manifest
                )
            },
            ensureStorageDirectory: { [weak manager] extensionID in
                _ = manager?.ensureWebExtensionStorageDirectoryExists(for: extensionID)
            },
            debugBeforePersist: { [weak manager] in
                #if DEBUG
                    manager?.testHooks.beforePersistInstalledRecord
                #else
                    nil
                #endif
            },
            trace: { [weak manager] message in manager?.runtimeDiagnostics.trace(message) }
        )
    }
}
