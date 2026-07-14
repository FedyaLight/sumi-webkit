import Foundation
import SwiftData

/// Applies user-visible enable, disable, and uninstall transitions.
/// Runtime loading and package installation remain separate capabilities.
@available(macOS 15.5, *)
@MainActor
final class InstalledExtensionLifecycleService {
    struct Environment {
        let modelContext: ModelContext
        let metadataStore: ExtensionInstallationMetadataStore
        let installedRecords: InstalledExtensionCollection
        let volatileRecords: ExtensionVolatileInstallationRecordReconciler
        let packageMaintenance: ExtensionPackageMaintenance
        let runtimeAccess: ExtensionRuntimeAccess
        let enabledRuntimeActivation: ExtensionEnabledRuntimeActivation
        let runtimeRecovery: ExtensionRuntimeRecovery
        let runtimeRetirement: ExtensionRuntimeRetirement
        let mutationRegistry: ExtensionRuntimeMutationRegistry
        let loadRegistry: ExtensionContextLoadRegistry
        let shutDownRuntime: @MainActor (String) ->
            ExtensionRuntimeShutdown.Result?
        let removeStoredData: @MainActor (
            String, ExtensionManager.WebExtensionStorageCleanupMode
        ) async -> Void
    }

    private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    func enable(_ extensionID: String) async throws -> InstalledExtension {
        guard let mutationLease = environment.mutationRegistry.begin(
            extensionID: extensionID,
            operation: .enable
        ) else {
            throw ExtensionError.installationFailed(
                "Another lifecycle operation is already running for this extension"
            )
        }
        defer { _ = environment.mutationRegistry.finish(mutationLease) }
        environment.loadRegistry.invalidate(extensionId: extensionID)
        try environment.volatileRecords.reconcile(extensionID)

        guard let entity = try environment.metadataStore.extensionEntity(for: extensionID) else {
            throw ExtensionError.installationFailed(
                "Extension was not found in persistence"
            )
        }

        let wasEnabled = entity.isEnabled
        guard let originalPersistedRecord = InstalledExtension(from: entity)
        else {
            throw ExtensionError.installationFailed(
                "Persisted extension metadata is invalid"
            )
        }
        let originalRecord = environment.installedRecords.records.first {
            $0.id == extensionID
        }
        let sourceKind =
            WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
        let activation: ExtensionLoadedContextFinalizer.Activation =
            sourceKind == .safariAppExtension && wasEnabled == false
            ? .safariAppExtension
            : .background(.enable)

        do {
            try environment.metadataStore.setEnabled(true, for: entity)
            let extensionRoot = try environment.metadataStore.extensionResourcesRoot(
                sourceKind: sourceKind,
                packagePath: entity.packagePath,
                sourceBundlePath: entity.sourceBundlePath
            )
            let manifest = try ExtensionManifestValidation.validate(
                at: extensionRoot.appendingPathComponent("manifest.json"),
                policy: WebExtensionManifestValidationPolicy.forSourceKind(sourceKind)
            )
            let refreshed = try environment.metadataStore.refreshedRecord(
                for: entity,
                manifest: manifest
            )
            publish { $0.upsert(refreshed) }

            guard let profileID = environment.runtimeAccess.resolvedProfileId(
                nil
            ) else {
                throw ExtensionError.installationFailed(
                    "Extension runtime profile is unavailable"
                )
            }
            if let loadedRecord = try await environment
                .enabledRuntimeActivation.activate(
                    entity: entity,
                    profileID: profileID,
                    activation: activation,
                    mutationLease: mutationLease
                ) {
                return loadedRecord
            }
            return refreshed
        } catch let enableError {
            guard wasEnabled == false else { throw enableError }
            if let transactionFailure =
                enableError as? ExtensionRuntimeTransactionFailure {
                switch transactionFailure.rollback.externalStateDisposition {
                case .rollbackAllowed:
                    break
                case .preserveForExactRuntime,
                     .preserveForReplacement,
                     .preserveForActiveBinding,
                     .preserveForCompetingTransaction,
                     .preserveUntilSharedCleanup:
                    throw ExtensionError.installationFailed(
                        "Enable failed after a WebKit runtime authority retained the extension; enabled persistence was preserved to match that authority. Original error: \(enableError.localizedDescription)"
                    )
                }
            }
            do {
                try restorePersistedRecord(
                    originalPersistedRecord,
                    entity: entity
                )
                publish { records in
                    if let originalRecord {
                        records.upsert(originalRecord)
                    } else {
                        records.upsert(originalPersistedRecord)
                    }
                }
            } catch let rollbackError {
                throw ExtensionError.installationFailed(
                    "Enable failed: \(enableError.localizedDescription). Persisted-state rollback also failed: \(rollbackError.localizedDescription)"
                )
            }
            throw enableError
        }
    }

    func disable(
        _ extensionID: String,
        releaseRuntimeIfIdle: Bool = true
    ) async throws {
        guard let mutationLease = environment.mutationRegistry.begin(
            extensionID: extensionID,
            operation: .disable
        ) else {
            throw ExtensionError.installationFailed(
                "Another lifecycle operation is already running for this extension"
            )
        }
        do {
            let shouldReleaseRuntime = try await disable(
                extensionID,
                mutationLease: mutationLease,
                releaseRuntimeIfIdle: releaseRuntimeIfIdle
            )
            _ = environment.mutationRegistry.finish(mutationLease)
            if shouldReleaseRuntime {
                performIdleRuntimeRelease(
                    "disableExtension.noEnabledExtensions"
                )
            }
        } catch {
            _ = environment.mutationRegistry.finish(mutationLease)
            throw error
        }
    }

    private func disable(
        _ extensionID: String,
        mutationLease: ExtensionRuntimeMutationLease,
        releaseRuntimeIfIdle: Bool
    ) async throws -> Bool {
        try environment.volatileRecords.reconcile(extensionID)
        let entity = try environment.metadataStore.extensionEntity(
            for: extensionID
        )
        let originalRecord = environment.installedRecords.records.first {
            $0.id == extensionID
        }
        let originalPersistedRecord = entity.flatMap(
            InstalledExtension.init(from:)
        )

        if let entity {
            do {
                try environment.metadataStore.setEnabled(false, for: entity)
            } catch let mutationError {
                guard let originalPersistedRecord else {
                    throw mutationError
                }
                do {
                    try restorePersistedRecord(
                        originalPersistedRecord,
                        entity: entity
                    )
                } catch let rollbackError {
                    throw ExtensionError.installationFailed(
                        "Disable persistence failed: \(mutationError.localizedDescription). Exact persisted-state rollback also failed: \(rollbackError.localizedDescription)"
                    )
                }
                throw mutationError
            }
        }
        publish { records in
            guard let index = records.records.firstIndex(where: {
                $0.id == extensionID
            }) else {
                return
            }
            let disabled = self.environment.metadataStore.record(
                records.records[index],
                withEnabledState: false
            )
            records.replace(at: index, with: disabled)
            records.sort()
        }

        let retirement = environment.runtimeRetirement.retire(
            extensionID: extensionID,
            cause: .disabled,
            mutationLease: mutationLease
        )
        guard retirement.completed else {
            guard retirement.completionStatus == .contextsRemaining else {
                throw CancellationError()
            }
            try await recoverIncompleteDisable(
                entity: entity,
                originalRecord: originalRecord,
                originalPersistedRecord: originalPersistedRecord,
                profileIDs: retirement.initialProfileIDs,
                mutationLease: mutationLease
            )
            throw ExtensionError.installationFailed(
                "Extension runtime could not be unloaded for profiles: "
                    + retirement.remainingProfileIDs.map(\.uuidString).sorted()
                    .joined(separator: ", ")
            )
        }

        return releaseRuntimeIfIdle && hasEnabledExtensions == false
    }

    private func recoverIncompleteDisable(
        entity: ExtensionEntity?,
        originalRecord: InstalledExtension?,
        originalPersistedRecord: InstalledExtension?,
        profileIDs: Set<UUID>,
        mutationLease: ExtensionRuntimeMutationLease
    ) async throws {
        guard let entity else {
            throw ExtensionError.installationFailed(
                "Extension runtime retirement was partial and no persisted record is available for recovery"
            )
        }

        var recoveryFailures: [String] = []
        do {
            guard let originalPersistedRecord else {
                throw ExtensionError.installationFailed(
                    "The original persisted extension record is unavailable"
                )
            }
            try restorePersistedRecord(
                originalPersistedRecord,
                entity: entity
            )
            publish { $0.upsert(originalRecord ?? originalPersistedRecord) }
        } catch {
            recoveryFailures.append(
                "enabled-state rollback failed: \(error.localizedDescription)"
            )
        }

        do {
            try await environment.runtimeRecovery.recoverEnabledRuntime(
                from: entity,
                profileIDs: profileIDs,
                mutationLease: mutationLease
            )
        } catch {
            recoveryFailures.append(
                "runtime recovery failed: \(error.localizedDescription)"
            )
        }

        guard recoveryFailures.isEmpty else {
            throw ExtensionError.installationFailed(
                "Extension disable was only partially retired and recovery was incomplete: "
                    + recoveryFailures.joined(separator: "; ")
            )
        }
    }

    func uninstall(_ extensionID: String) async throws {
        guard let mutationLease = environment.mutationRegistry.begin(
            extensionID: extensionID,
            operation: .uninstall
        ) else {
            throw ExtensionError.installationFailed(
                "Another lifecycle operation is already running for this extension"
            )
        }
        do {
            _ = try await disable(
                extensionID,
                mutationLease: mutationLease,
                releaseRuntimeIfIdle: false
            )
            try validate(mutationLease)
            guard environment.mutationRegistry.enterIrreversiblePhase(
                mutationLease
            ) else {
                throw CancellationError()
            }
            await environment.removeStoredData(
                extensionID,
                .pruneDirectoryIfPossible
            )
            try validate(mutationLease)

            var copiedPackageURL: URL?
            if let entity = try environment.metadataStore.extensionEntity(
                for: extensionID
            ) {
                let sourceKind =
                    WebExtensionSourceKind(rawValue: entity.sourceKindRawValue)
                    ?? .directory
                if sourceKind == .directory {
                    copiedPackageURL = URL(
                        fileURLWithPath: entity.packagePath,
                        isDirectory: true
                    )
                }
                environment.modelContext.delete(entity)
                try environment.modelContext.save()
            }

            publish { $0.remove(id: extensionID) }
            if let copiedPackageURL,
               FileManager.default.fileExists(atPath: copiedPackageURL.path) {
                do {
                    let quarantined = try environment.packageMaintenance
                        .quarantinePackage(copiedPackageURL)
                    environment.packageMaintenance
                        .deleteQuarantinedPackages([quarantined])
                } catch {
                    ExtensionManager.logger.error(
                        "Uninstalled extension metadata but left its package for startup cleanup: \(error.localizedDescription, privacy: .public)"
                    )
                }
            }
            let shouldReleaseRuntime = hasEnabledExtensions == false
            _ = environment.mutationRegistry.finish(mutationLease)
            if shouldReleaseRuntime {
                performIdleRuntimeRelease(
                    "uninstallExtension.noEnabledExtensions"
                )
            }
        } catch {
            _ = environment.mutationRegistry.finish(mutationLease)
            throw error
        }
    }

    private var hasEnabledExtensions: Bool {
        environment.installedRecords.records.contains { $0.isEnabled }
    }

    private func publish(
        _ mutation: (InstalledExtensionCollection) -> Void
    ) {
        mutation(environment.installedRecords)
    }

    private func restorePersistedRecord(
        _ record: InstalledExtension,
        entity: ExtensionEntity
    ) throws {
        environment.metadataStore.update(entity, from: record)
        try environment.modelContext.save()
    }

    private func performIdleRuntimeRelease(_ reason: String) {
        guard let result = environment.shutDownRuntime(reason) else { return }
        switch result.completionStatus {
        case .completed, .mutationInProgress:
            break
        case .contextsRemaining, .superseded:
            ExtensionManager.logger.error(
                "Idle extension runtime release did not complete for \(reason, privacy: .public): \(String(describing: result.completionStatus), privacy: .public)"
            )
        }
    }

    private func validate(_ lease: ExtensionRuntimeMutationLease) throws {
        guard environment.mutationRegistry.isCurrent(lease) else {
            throw CancellationError()
        }
    }
}

@available(macOS 15.5, *)
extension InstalledExtensionLifecycleService.Environment {
    @MainActor
    static func makeLive(manager: ExtensionManager) -> Self {
        Self(
            modelContext: manager.context,
            metadataStore: manager.installationMetadataStore,
            installedRecords: manager.installedExtensionCollection,
            volatileRecords: ExtensionVolatileInstallationRecordReconciler(
                persistence: manager.installationMetadataStore,
                installedRecords: manager.installedExtensionCollection
            ),
            packageMaintenance: ExtensionPackageMaintenance(
                layout: ExtensionPackageLayout(
                    extensionsRoot: ExtensionPathSafety.extensionsDirectory()
                ),
                activeGenerations: manager.activePackageGenerations
            ),
            runtimeAccess: manager.extensionRuntimeAccess,
            enabledRuntimeActivation: manager.enabledRuntimeActivation,
            runtimeRecovery: manager.runtimeRecovery,
            runtimeRetirement: manager.runtimeRetirement,
            mutationRegistry: manager.runtimeMutationRegistry,
            loadRegistry: manager.contextLoadRegistry,
            shutDownRuntime: { [weak manager] reason in
                guard let manager else { return nil }
                let result = manager.shutDownExtensionRuntime(
                    reason: reason,
                    admission: .ifNoScopedMutations
                )
                if result.completed {
                    _ = manager.executeExtensionRuntimeRebuildPlan(
                        result.tabRebuildPlan,
                        reason: reason
                    )
                }
                return result
            },
            removeStoredData: { [weak manager] extensionID, mode in
                await manager?.removeStoredWebExtensionData(for: extensionID, mode: mode)
            }
        )
    }
}
