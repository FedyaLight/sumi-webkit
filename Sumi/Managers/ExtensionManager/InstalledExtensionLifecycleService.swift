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
        let runtimeLoader: ExtensionRuntimeLoader
        let tearDownAllRuntime: @MainActor (String, Bool, Bool) -> Void
        let removeStoredData: @MainActor (
            String, ExtensionManager.WebExtensionStorageCleanupMode
        ) async -> Void
    }

    private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    func enable(_ extensionID: String) async throws -> InstalledExtension {
        guard let entity = try environment.metadataStore.extensionEntity(for: extensionID) else {
            throw ExtensionError.installationFailed(
                "Extension was not found in persistence"
            )
        }

        let wasEnabled = entity.isEnabled
        let originalRecord = environment.installedRecords.records.first {
            $0.id == extensionID
        }
        let sourceKind =
            WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
        let activation: ExtensionRuntimeLoader.EnableActivation =
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
            let manifest = try ExtensionUtils.validateManifest(
                at: extensionRoot.appendingPathComponent("manifest.json"),
                policy: WebExtensionManifestValidationPolicy.forSourceKind(sourceKind)
            )
            let refreshed = try environment.metadataStore.refreshedRecord(
                for: entity,
                manifest: manifest
            )
            await publish { $0.upsert(refreshed) }

            guard let profileID = environment.runtimeLoader.resolvedProfileID() else {
                throw ExtensionError.installationFailed(
                    "Extension runtime profile is unavailable"
                )
            }
            environment.runtimeLoader.ensureController(for: profileID)
            if environment.runtimeLoader.hasLoadedContext(
                extensionID: extensionID,
                profileID: profileID
            ) == false {
                return try await environment.runtimeLoader.loadEnabled(
                    from: entity,
                    profileID: profileID,
                    activation: activation
                )
            }

            await environment.runtimeLoader.finalizeAlreadyLoadedRuntime(
                extensionID: extensionID,
                profileID: profileID,
                activation: activation
            )
            return refreshed
        } catch let enableError {
            guard wasEnabled == false else { throw enableError }
            do {
                try environment.metadataStore.setEnabled(false, for: entity)
                await publish { records in
                    if let originalRecord {
                        records.upsert(originalRecord)
                    } else {
                        records.remove(id: extensionID)
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
        if let entity = try environment.metadataStore.extensionEntity(for: extensionID) {
            try environment.metadataStore.setEnabled(false, for: entity)
        }

        environment.runtimeLoader.resetRuntimeState(
            extensionID: extensionID,
            removeUIState: true
        )
        await publish { records in
            guard let index = records.records.firstIndex(where: { $0.id == extensionID }) else {
                return
            }
            let disabled = self.environment.metadataStore.record(
                records.records[index],
                withEnabledState: false
            )
            records.replace(at: index, with: disabled)
            records.sort()
        }

        if releaseRuntimeIfIdle && hasEnabledExtensions == false {
            environment.tearDownAllRuntime(
                "disableExtension.noEnabledExtensions",
                true,
                true
            )
        }
    }

    func uninstall(_ extensionID: String) async throws {
        try await disable(extensionID, releaseRuntimeIfIdle: false)
        await environment.removeStoredData(extensionID, .pruneDirectoryIfPossible)

        if let entity = try environment.metadataStore.extensionEntity(for: extensionID) {
            let sourceKind =
                WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            let packageURL = URL(fileURLWithPath: entity.packagePath, isDirectory: true)
            if sourceKind == .directory,
               FileManager.default.fileExists(atPath: packageURL.path) {
                try FileManager.default.removeItem(at: packageURL)
            }
            environment.modelContext.delete(entity)
            try environment.modelContext.save()
        }

        await publish { $0.remove(id: extensionID) }
        if hasEnabledExtensions == false {
            environment.tearDownAllRuntime(
                "uninstallExtension.noEnabledExtensions",
                true,
                true
            )
        }
    }

    private var hasEnabledExtensions: Bool {
        environment.installedRecords.records.contains { $0.isEnabled }
    }

    private func publish(
        _ mutation: @escaping @MainActor (InstalledExtensionCollection) -> Void
    ) async {
        await withCheckedContinuation { continuation in
            Task { @MainActor [installedRecords = environment.installedRecords] in
                await Task.yield()
                mutation(installedRecords)
                continuation.resume(returning: ())
            }
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
            runtimeLoader: manager.extensionRuntimeLoader,
            tearDownAllRuntime: { [weak manager] reason, removeUIState, releaseController in
                manager?.tearDownExtensionRuntime(
                    reason: reason,
                    removeUIState: removeUIState,
                    releaseController: releaseController
                )
            },
            removeStoredData: { [weak manager] extensionID, mode in
                await manager?.removeStoredWebExtensionData(for: extensionID, mode: mode)
            }
        )
    }
}
