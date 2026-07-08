import Foundation
import SwiftData
import WebKit

/// Owns extension installation flows: installing from a source URL, enabling,
/// disabling, uninstalling, loading installed metadata, and loading enabled
/// extensions into the runtime with rollback on failure.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInstallationFlowOwner {
    struct Dependencies {
        let modelContext: ModelContext
        let installationMetadataStore: ExtensionInstallationMetadataStore
        let isExtensionSupportAvailable: @MainActor () -> Bool
        let extensionEntity: @MainActor (String) throws -> ExtensionEntity?
        let extensionResourcesRoot: @MainActor (WebExtensionSourceKind, String, String) throws -> URL
        let refreshedRecord: @MainActor (ExtensionEntity, [String: Any]) throws -> InstalledExtension
        let upsertInstalledExtension: @MainActor (InstalledExtension) -> Void
        let installedExtensions: @MainActor () -> [InstalledExtension]
        let replaceInstalledExtension: @MainActor (Int, InstalledExtension) -> Void
        let removeInstalledExtension: @MainActor (String) -> Void
        let setInstalledExtensions: @MainActor ([InstalledExtension]) -> Void
        let sortInstalledExtensions: @MainActor () -> Void
        let reconcilePinnedToolbarExtensions: @MainActor () -> Void
        let setExtensionsLoaded: @MainActor (Bool) -> Void
        let fallbackProfileId: @MainActor () -> UUID?
        let resolvedProfileId: @MainActor (UUID?) -> UUID?
        let ensureExtensionController: @MainActor (UUID) -> Void
        let getExtensionContext: @MainActor (String, UUID) -> WKWebExtensionContext?
        let finalizeEnabledExtensionRuntime: @MainActor (
            String, UUID, ExtensionManager.ExtensionBackgroundWakeReason?
        ) async -> Void
        let tearDownExtensionRuntimeState: @MainActor (String, Bool) -> Void
        let tearDownExtensionRuntime: @MainActor (String, Bool, Bool) -> Void
        let hasEnabledInstalledExtensions: @MainActor () -> Bool
        let removeStoredWebExtensionData: @MainActor (
            String, ExtensionManager.WebExtensionStorageCleanupMode
        ) async -> Void
        let hasStoredWebExtensionDataCandidate: @MainActor (String) -> Bool
        let traceWebExtensionStoreLifecycle: @MainActor (String, String, [String: Any]?) -> Void
        let ensureWebExtensionStorageDirectoryExists: @MainActor (String) -> Void
        let requestExtensionRuntimeAndWait: @MainActor (
            ExtensionManager.ExtensionRuntimeRequestReason, Bool
        ) async -> Void
        let resolveInstallSource: @MainActor (URL) throws -> ExtensionInstallSourceResolver.ResolvedInstallSource
        let validateMV3Requirements: @MainActor ([String: Any], URL) throws -> Void
        let makeInstalledRecord: @MainActor (
            String, [String: Any], URL, Bool, WebExtensionSourceKind, String, URL, ExtensionEntity?
        ) throws -> InstalledExtension
        let persistRecord: @MainActor (InstalledExtension) throws -> Void
        let updateEntity: @MainActor (ExtensionEntity, InstalledExtension) -> Void
        let extensionLoadGeneration: @MainActor () -> UInt64
        let loadRuntimeContext: @MainActor (
            ExtensionRuntimeContextLoadOwner.Request
        ) async throws -> WKWebExtensionContext
        let activateInstallRuntime: @MainActor (
            ExtensionInstallRuntimeActivationOwner.Request
        ) async -> Void
        let recordRuntimeMetric: @MainActor (
            String, (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void
        ) -> Void
        let clearExtensionLoadError: @MainActor (String, UUID) -> Void
        let recordExtensionLoadError: @MainActor (Error, String, UUID) -> Void
        let touchLiveExtensionContext: @MainActor (String, UUID) -> Void
        let enforceBoundedLiveExtensionContexts: @MainActor (UUID, String) -> Void
        let markExtensionRuntimeReadyIfProfileContextsLoaded: @MainActor (UUID) -> Void
        let logExtensionLoadFailure: @MainActor (Error, String, UUID, String) -> Void
        let liveExtensionContextsCount: @MainActor () -> Int
        let trace: @MainActor (String) -> Void
        /// Debug-only persistence hook; returns nil in release builds.
        let debugBeforePersistInstalledRecord: @MainActor () -> ((InstalledExtension) throws -> Void)?
    }

    private let dependencies: Dependencies

    private enum EnabledExtensionRuntimeActivation {
        case standard(backgroundWakeReason: ExtensionManager.ExtensionBackgroundWakeReason?)
        case safariAppExtensionEnable

        func loadOperation(
            expectedGeneration: UInt64
        ) -> ExtensionRuntimeContextLoadOwner.Operation {
            switch self {
            case .standard:
                return .loadEnabled(expectedGeneration: expectedGeneration)
            case .safariAppExtensionEnable:
                return .safariEnable
            }
        }
    }

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    /// Delivers install results on the next main runloop turn so SwiftUI does not emit
    /// "Publishing changes from within view updates" when UI callbacks mutate `@Published` state.
    private func deliverInstallCompletion(
        _ result: Result<InstalledExtension, ExtensionError>,
        to completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        Task { @MainActor in
            await Task.yield()
            completionHandler(result)
        }
    }

    private func applyInstalledExtensionsMutationOnNextRunLoop(
        _ mutation: @escaping @MainActor () -> Void
    ) async {
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                await Task.yield()
                mutation()
                continuation.resume(returning: ())
            }
        }
    }

    private func resolvedExtensionID(
        manifest: [String: Any],
        existingEntity: ExtensionEntity?,
        preferredBundleIdentifier: String? = nil
    ) throws -> String {
        let rawExtensionId: String
        if let existingEntity {
            rawExtensionId = existingEntity.id
        } else if let preferredBundleIdentifier,
                  preferredBundleIdentifier.isEmpty == false {
            rawExtensionId = preferredBundleIdentifier
        } else if let geckoId = Self.geckoExtensionID(from: manifest) {
            rawExtensionId = geckoId
        } else {
            rawExtensionId = UUID().uuidString
        }

        return try ExtensionUtils.validateExtensionIDPathComponent(rawExtensionId)
    }

    private static func geckoExtensionID(from manifest: [String: Any]) -> String? {
        guard let browserSpecificSettings = manifest["browser_specific_settings"] as? [String: Any],
              let gecko = browserSpecificSettings["gecko"] as? [String: Any]
        else {
            return nil
        }
        return gecko["id"] as? String
    }

    func installExtension(
        from sourceURL: URL,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        guard dependencies.isExtensionSupportAvailable() else {
            deliverInstallCompletion(.failure(.unsupportedOS), to: completionHandler)
            return
        }

        Task {
            do {
                let installed = try await performInstallation(from: sourceURL)
                deliverInstallCompletion(.success(installed), to: completionHandler)
            } catch let error as ExtensionError {
                deliverInstallCompletion(.failure(error), to: completionHandler)
            } catch {
                deliverInstallCompletion(
                    .failure(.installationFailed(error.localizedDescription)),
                    to: completionHandler
                )
            }
        }
    }

    func enableExtension(_ extensionId: String) async throws -> InstalledExtension {
        guard let entity = try dependencies.extensionEntity(extensionId) else {
            throw ExtensionError.installationFailed("Extension was not found in persistence")
        }

        let wasEnabledBeforeToggle = entity.isEnabled
        let sourceKind =
            WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
        let runtimeActivation = enableRuntimeActivation(
            sourceKind: sourceKind,
            wasEnabledBeforeToggle: wasEnabledBeforeToggle
        )

        try dependencies.installationMetadataStore.setEnabled(true, for: entity)
        let extensionRoot = try dependencies.extensionResourcesRoot(
            sourceKind,
            entity.packagePath,
            entity.sourceBundlePath
        )
        let manifest = try ExtensionUtils.validateManifest(
            at: extensionRoot.appendingPathComponent("manifest.json"),
            policy: WebExtensionManifestValidationPolicy.forSourceKind(sourceKind)
        )
        let refreshed = try dependencies.refreshedRecord(entity, manifest)
        await applyInstalledExtensionsMutationOnNextRunLoop { [dependencies] in
            dependencies.upsertInstalledExtension(refreshed)
        }
        loadInstalledExtensionMetadata()

        let enableProfileId = dependencies.fallbackProfileId()
        guard let enableProfileId else {
            throw ExtensionError.installationFailed(
                "Extension runtime profile is unavailable"
            )
        }

        dependencies.ensureExtensionController(enableProfileId)
        if dependencies.getExtensionContext(extensionId, enableProfileId) == nil {
            return try await loadEnabledExtension(
                from: entity,
                profileId: enableProfileId,
                postLoadActivation: runtimeActivation
            )
        }

        await finalizeAlreadyLoadedEnabledExtensionRuntime(
            extensionId,
            enableProfileId,
            activation: runtimeActivation
        )
        return refreshed
    }

    func disableExtension(
        _ extensionId: String,
        releaseRuntimeIfIdle: Bool = true
    ) async throws {
        dependencies.tearDownExtensionRuntimeState(extensionId, true)

        if let entity = try dependencies.extensionEntity(extensionId) {
            try dependencies.installationMetadataStore.setEnabled(false, for: entity)
        }

        await applyInstalledExtensionsMutationOnNextRunLoop { [dependencies] in
            guard let index = dependencies.installedExtensions()
                .firstIndex(where: { $0.id == extensionId })
            else {
                return
            }

            let current = dependencies.installedExtensions()[index]
            let updated = dependencies.installationMetadataStore.record(
                current,
                withEnabledState: false
            )
            dependencies.replaceInstalledExtension(index, updated)
            dependencies.sortInstalledExtensions()
        }

        if releaseRuntimeIfIdle && dependencies.hasEnabledInstalledExtensions() == false {
            dependencies.tearDownExtensionRuntime(
                "disableExtension.noEnabledExtensions",
                true,
                true
            )
        }
    }

    func uninstallExtension(_ extensionId: String) async throws {
        try await disableExtension(extensionId, releaseRuntimeIfIdle: false)
        await dependencies.removeStoredWebExtensionData(extensionId, .pruneDirectoryIfPossible)

        if let entity = try dependencies.extensionEntity(extensionId) {
            let sourceKind = WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            let packageURL = URL(fileURLWithPath: entity.packagePath, isDirectory: true)
            if sourceKind == .directory,
               FileManager.default.fileExists(atPath: packageURL.path) {
                try FileManager.default.removeItem(at: packageURL)
            }
            dependencies.modelContext.delete(entity)
            try dependencies.modelContext.save()
        }

        await applyInstalledExtensionsMutationOnNextRunLoop { [dependencies] in
            dependencies.removeInstalledExtension(extensionId)
        }

        if dependencies.hasEnabledInstalledExtensions() == false {
            dependencies.tearDownExtensionRuntime(
                "uninstallExtension.noEnabledExtensions",
                true,
                true
            )
        }
    }

    @discardableResult
    func loadInstalledExtensionMetadata() -> [ExtensionEntity] {
        let signpostState = PerformanceTrace.beginInterval(
            "ExtensionManager.loadInstalledExtensionMetadata"
        )
        defer {
            PerformanceTrace.endInterval(
                "ExtensionManager.loadInstalledExtensionMetadata",
                signpostState
            )
        }

        dependencies.trace(
            "loadInstalledExtensionMetadata start installedContexts=\(dependencies.liveExtensionContextsCount())"
        )

        let result = dependencies.installationMetadataStore.loadInstalledExtensionMetadata {
            dependencies.trace($0)
        }
        return applyInstalledExtensionMetadataLoadResult(result)
    }

    @discardableResult
    func applyInstalledExtensionMetadataLoadResult(
        _ result: ExtensionInstallationMetadataStore.MetadataLoadResult
    ) -> [ExtensionEntity] {
        dependencies.setInstalledExtensions(result.records)
        if result.didFetchPersistedMetadata {
            dependencies.reconcilePinnedToolbarExtensions()
        }
        dependencies.setExtensionsLoaded(true)
        dependencies.trace(
            "loadInstalledExtensionMetadata complete records=\(result.records.count) enabled=\(result.enabledEntities.count)"
        )
        return result.enabledEntities
    }

    func loadEnabledExtension(
        from entity: ExtensionEntity,
        profileId: UUID? = nil,
        expectedLoadGeneration: UInt64? = nil,
        postLoadBackgroundWakeReason: ExtensionManager.ExtensionBackgroundWakeReason? = nil
    ) async throws -> InstalledExtension {
        try await loadEnabledExtension(
            from: entity,
            profileId: profileId,
            expectedLoadGeneration: expectedLoadGeneration,
            postLoadActivation: .standard(backgroundWakeReason: postLoadBackgroundWakeReason)
        )
    }

    private func loadEnabledExtension(
        from entity: ExtensionEntity,
        profileId: UUID? = nil,
        expectedLoadGeneration: UInt64? = nil,
        postLoadActivation: EnabledExtensionRuntimeActivation
    ) async throws -> InstalledExtension {
        let loadGeneration = expectedLoadGeneration ?? dependencies.extensionLoadGeneration()
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.loadEnabledExtension")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.loadEnabledExtension", signpostState)
        }

        do {
            let resolvedProfileId = dependencies.resolvedProfileId(profileId)
            guard let resolvedProfileId else {
                throw ExtensionError.installationFailed(
                    "Extension runtime profile is unavailable"
                )
            }
            let sourceKind =
                WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            let extensionRoot = try dependencies.extensionResourcesRoot(
                sourceKind,
                entity.packagePath,
                entity.sourceBundlePath
            )
            let manifestURL = extensionRoot.appendingPathComponent("manifest.json")
            dependencies.trace(
                "loadEnabledExtension start extensionId=\(entity.id) profileId=\(resolvedProfileId.uuidString) expectedGeneration=\(loadGeneration) currentGeneration=\(dependencies.extensionLoadGeneration()) packagePath=\(extensionRoot.path)"
            )
            let validationStart = CFAbsoluteTimeGetCurrent()
            let manifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: WebExtensionManifestValidationPolicy.forSourceKind(sourceKind)
            )
            dependencies.recordRuntimeMetric(entity.id) {
                $0.manifestValidationDuration = CFAbsoluteTimeGetCurrent() - validationStart
            }
            let extensionContext = try await dependencies.loadRuntimeContext(
                ExtensionRuntimeContextLoadOwner.Request(
                    extensionId: entity.id,
                    profileId: resolvedProfileId,
                    sourceKind: sourceKind,
                    sourceBundlePath: entity.sourceBundlePath,
                    packageRoot: extensionRoot,
                    manifest: manifest,
                    operation: postLoadActivation.loadOperation(
                        expectedGeneration: loadGeneration
                    )
                )
            )

            dependencies.clearExtensionLoadError(entity.id, resolvedProfileId)
            dependencies.touchLiveExtensionContext(entity.id, resolvedProfileId)
            dependencies.enforceBoundedLiveExtensionContexts(resolvedProfileId, entity.id)

            await finalizeLoadedEnabledExtensionRuntime(
                entity.id,
                resolvedProfileId,
                extensionContext: extensionContext,
                activation: postLoadActivation
            )

            let refreshed = try dependencies.refreshedRecord(entity, manifest)
            await applyInstalledExtensionsMutationOnNextRunLoop { [dependencies] in
                dependencies.upsertInstalledExtension(refreshed)
            }
            dependencies.updateEntity(entity, refreshed)
            try dependencies.modelContext.save()
            return refreshed
        } catch {
            let errorProfileId = dependencies.resolvedProfileId(profileId)
            if let errorProfileId {
                dependencies.recordExtensionLoadError(error, entity.id, errorProfileId)
            }
            dependencies.tearDownExtensionRuntimeState(entity.id, false)
            throw error
        }
    }

    private func enableRuntimeActivation(
        sourceKind: WebExtensionSourceKind,
        wasEnabledBeforeToggle: Bool
    ) -> EnabledExtensionRuntimeActivation {
        if sourceKind == .safariAppExtension,
           wasEnabledBeforeToggle == false {
            return .safariAppExtensionEnable
        }

        return .standard(backgroundWakeReason: .enable)
    }

    private func finalizeAlreadyLoadedEnabledExtensionRuntime(
        _ extensionId: String,
        _ profileId: UUID,
        activation: EnabledExtensionRuntimeActivation
    ) async {
        guard let extensionContext = dependencies.getExtensionContext(
            extensionId,
            profileId
        ) else {
            return
        }

        await finalizeLoadedEnabledExtensionRuntime(
            extensionId,
            profileId,
            extensionContext: extensionContext,
            activation: activation
        )
    }

    private func finalizeLoadedEnabledExtensionRuntime(
        _ extensionId: String,
        _ profileId: UUID,
        extensionContext: WKWebExtensionContext,
        activation: EnabledExtensionRuntimeActivation
    ) async {
        switch activation {
        case .standard(let backgroundWakeReason):
            await dependencies.finalizeEnabledExtensionRuntime(
                extensionId,
                profileId,
                backgroundWakeReason
            )
            dependencies.markExtensionRuntimeReadyIfProfileContextsLoaded(profileId)
        case .safariAppExtensionEnable:
            await dependencies.activateInstallRuntime(
                ExtensionInstallRuntimeActivationOwner.Request(
                    profileId: profileId,
                    extensionContext: extensionContext,
                    installedExtensionId: extensionId,
                    operation: .safariEnable
                )
            )
        }
    }

    func performInstallation(
        from sourceURL: URL,
        enableOnInstall: Bool = true
    ) async throws -> InstalledExtension {
        if enableOnInstall {
            await dependencies.requestExtensionRuntimeAndWait(.install, true)
        }

        let resolvedSource = try dependencies.resolveInstallSource(sourceURL)
        if resolvedSource.sourceKind == .safariAppExtension {
            return try await enableDiscoveredSafariAppExtension(
                resolvedSource,
                enableOnInstall: enableOnInstall
            )
        }

        let extensionsDirectory = ExtensionUtils.extensionsDirectory()
        let temporaryDirectory = extensionsDirectory.appendingPathComponent(
            "temp_\(UUID().uuidString)",
            isDirectory: true
        )

        if FileManager.default.fileExists(atPath: temporaryDirectory.path) {
            try FileManager.default.removeItem(at: temporaryDirectory)
        }

        var finalDirectory: URL?
        var backupDirectory: URL?
        var installedExtensionID: String?
        var existingEntitySnapshot: ExtensionEntity?
        var shouldRestoreExistingRuntime = false

        do {
            try FileManager.default.copyItem(
                at: resolvedSource.resourcesURL,
                to: temporaryDirectory
            )

            let manifestPolicy = WebExtensionManifestValidationPolicy.forSourceKind(
                resolvedSource.sourceKind
            )
            let manifestURL = temporaryDirectory.appendingPathComponent("manifest.json")
            let manifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: manifestPolicy
            )
            try dependencies.validateMV3Requirements(manifest, temporaryDirectory)

            let allEntities = try dependencies.modelContext.fetch(FetchDescriptor<ExtensionEntity>())
            let existingEntityBySource = allEntities.first {
                $0.sourceBundlePath == resolvedSource.sourceBundlePath.path
            }
            let extensionId = try resolvedExtensionID(
                manifest: manifest,
                existingEntity: existingEntityBySource
            )

            installedExtensionID = extensionId

            let destinationDirectory = try ExtensionUtils.extensionDirectory(
                forExtensionID: extensionId,
                under: extensionsDirectory
            )
            finalDirectory = destinationDirectory
            existingEntitySnapshot = try dependencies.extensionEntity(extensionId)
            shouldRestoreExistingRuntime = existingEntitySnapshot?.isEnabled == true

            if FileManager.default.fileExists(atPath: destinationDirectory.path) {
                let existingBackup = extensionsDirectory.appendingPathComponent(
                    "backup_\(extensionId)_\(UUID().uuidString)",
                    isDirectory: true
                )
                try FileManager.default.moveItem(at: destinationDirectory, to: existingBackup)
                backupDirectory = existingBackup
            }

            if let existingEntitySnapshot {
                dependencies.tearDownExtensionRuntimeState(existingEntitySnapshot.id, false)
            } else if resolvedSource.sourceKind == .safariAppExtension {
                // Safari parity: reinstalling a Safari app extension keeps its
                // WebKit data — Safari preserves extension state across
                // reinstall and containing-app updates.
                if RuntimeDiagnostics.isVerboseEnabled {
                    dependencies.trace(
                        "Preserved WebExtension data for \(extensionId): Safari app extension reinstall keeps state"
                    )
                }
            } else if dependencies.hasStoredWebExtensionDataCandidate(extensionId) {
                dependencies.traceWebExtensionStoreLifecycle(
                    "before-install-cleanup",
                    extensionId,
                    manifest
                )
                await dependencies.removeStoredWebExtensionData(
                    extensionId,
                    .preserveDirectoryForImmediateRuntimeLoad
                )
                dependencies.traceWebExtensionStoreLifecycle(
                    "after-install-cleanup",
                    extensionId,
                    manifest
                )
            } else {
                if RuntimeDiagnostics.isVerboseEnabled {
                    dependencies.trace(
                        "Skipped WebExtension data cleanup for \(extensionId): no stored data candidate (fresh install path)"
                    )
                }
            }

            try FileManager.default.moveItem(at: temporaryDirectory, to: destinationDirectory)

            let finalManifestURL = destinationDirectory.appendingPathComponent("manifest.json")
            let finalManifest = try ExtensionUtils.validateManifest(
                at: finalManifestURL,
                policy: manifestPolicy
            )

            let record = try dependencies.makeInstalledRecord(
                extensionId,
                finalManifest,
                destinationDirectory,
                enableOnInstall,
                resolvedSource.sourceKind,
                resolvedSource.sourceBundlePath.path,
                resolvedSource.sourceFingerprintURL,
                existingEntitySnapshot
            )

            if enableOnInstall {
                let installProfileId = dependencies.fallbackProfileId()
                guard let installProfileId else {
                    throw ExtensionError.installationFailed(
                        "Extension runtime profile is unavailable"
                    )
                }
                let extensionContext = try await dependencies.loadRuntimeContext(
                    ExtensionRuntimeContextLoadOwner.Request(
                        extensionId: extensionId,
                        profileId: installProfileId,
                        sourceKind: resolvedSource.sourceKind,
                        sourceBundlePath: resolvedSource.sourceBundlePath.path,
                        packageRoot: destinationDirectory,
                        manifest: finalManifest,
                        operation: .install
                    )
                )

                await dependencies.activateInstallRuntime(
                    ExtensionInstallRuntimeActivationOwner.Request(
                        profileId: installProfileId,
                        extensionContext: extensionContext,
                        installedExtensionId: record.id,
                        operation: .install
                    )
                )
            } else {
                dependencies.ensureWebExtensionStorageDirectoryExists(extensionId)
            }

            if let beforePersist = dependencies.debugBeforePersistInstalledRecord() {
                try beforePersist(record)
            }
            try dependencies.persistRecord(record)
            await applyInstalledExtensionsMutationOnNextRunLoop { [dependencies] in
                dependencies.upsertInstalledExtension(record)
            }

            if let backupDirectory {
                removeInstallArtifactIfPresent(
                    backupDirectory,
                    reason: "discarding extension package backup after successful install"
                )
            }

            return record
        } catch {
            if let installedExtensionID {
                dependencies.tearDownExtensionRuntimeState(installedExtensionID, false)
            }

            if let finalDirectory {
                removeInstallArtifactIfPresent(
                    finalDirectory,
                    reason: "removing failed extension install destination"
                )
            }

            removeInstallArtifactIfPresent(
                temporaryDirectory,
                reason: "removing failed extension install staging directory"
            )

            if let backupDirectory, let finalDirectory {
                restoreInstallBackup(
                    backupDirectory: backupDirectory,
                    finalDirectory: finalDirectory
                )
            }

            if shouldRestoreExistingRuntime, let existingEntitySnapshot {
                do {
                    _ = try await loadEnabledExtension(from: existingEntitySnapshot)
                } catch let restoreError {
                    if let restoreProfileId = dependencies.fallbackProfileId() {
                        dependencies.logExtensionLoadFailure(
                            restoreError,
                            existingEntitySnapshot.id,
                            restoreProfileId,
                            "restore existing runtime after failed installation"
                        )
                    } else {
                        ExtensionManager.logger.error(
                            "Failed to restore existing runtime after failed installation for extension \(existingEntitySnapshot.id, privacy: .public): \(restoreError.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }

            throw error
        }
    }

    private func removeInstallArtifactIfPresent(_ url: URL, reason: String) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }
        do {
            try FileManager.default.removeItem(at: url)
        } catch {
            ExtensionManager.logger.error(
                "Failed \(reason, privacy: .public) at \(url.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func restoreInstallBackup(backupDirectory: URL, finalDirectory: URL) {
        removeInstallArtifactIfPresent(
            finalDirectory,
            reason: "removing failed extension install destination before restoring backup"
        )
        do {
            try FileManager.default.moveItem(at: backupDirectory, to: finalDirectory)
        } catch {
            ExtensionManager.logger.error(
                "Failed to restore extension package backup from \(backupDirectory.path, privacy: .public) to \(finalDirectory.path, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    private func enableDiscoveredSafariAppExtension(
        _ resolvedSource: ExtensionInstallSourceResolver.ResolvedInstallSource,
        enableOnInstall: Bool
    ) async throws -> InstalledExtension {
        guard resolvedSource.sourceKind == .safariAppExtension,
              let appexBundleURL = resolvedSource.appexBundleURL,
              let bundle = Bundle(url: appexBundleURL)
        else {
            throw ExtensionError.installationFailed(
                "Installed Safari app extension bundle is unavailable"
            )
        }

        let extensionRoot = resolvedSource.resourcesURL
        let manifestPolicy = WebExtensionManifestValidationPolicy.forSourceKind(
            resolvedSource.sourceKind
        )
        let manifestURL = extensionRoot.appendingPathComponent("manifest.json")
        let manifest = try ExtensionUtils.validateManifest(
            at: manifestURL,
            policy: manifestPolicy
        )
        try dependencies.validateMV3Requirements(manifest, extensionRoot)

        let allEntities = try dependencies.modelContext.fetch(FetchDescriptor<ExtensionEntity>())
        let existingEntityBySource = allEntities.first {
            URL(fileURLWithPath: $0.sourceBundlePath, isDirectory: true)
                .standardizedFileURL.path == resolvedSource.sourceBundlePath.standardizedFileURL.path
        }
        let extensionId = try resolvedExtensionID(
            manifest: manifest,
            existingEntity: existingEntityBySource,
            preferredBundleIdentifier: bundle.bundleIdentifier
        )

        let existingEntitySnapshot: ExtensionEntity?
        if let existingEntityBySource {
            existingEntitySnapshot = existingEntityBySource
        } else {
            existingEntitySnapshot = try dependencies.extensionEntity(extensionId)
        }
        let shouldRestoreExistingRuntime = existingEntitySnapshot?.isEnabled == true

        do {
            if let existingEntitySnapshot {
                dependencies.tearDownExtensionRuntimeState(existingEntitySnapshot.id, false)
            }
            // Safari parity: reinstalling or updating a Safari app extension
            // keeps its WebKit data (sessions survive extension updates in
            // Safari). Stale-data cleanup applies only to directory sources.

            let record = try dependencies.makeInstalledRecord(
                extensionId,
                manifest,
                extensionRoot,
                enableOnInstall,
                resolvedSource.sourceKind,
                resolvedSource.sourceBundlePath.path,
                resolvedSource.sourceFingerprintURL,
                existingEntitySnapshot
            )

            if enableOnInstall {
                let installProfileId = dependencies.fallbackProfileId()
                guard let installProfileId else {
                    throw ExtensionError.installationFailed(
                        "Extension runtime profile is unavailable"
                    )
                }
                let extensionContext = try await dependencies.loadRuntimeContext(
                    ExtensionRuntimeContextLoadOwner.Request(
                        extensionId: extensionId,
                        profileId: installProfileId,
                        sourceKind: resolvedSource.sourceKind,
                        sourceBundlePath: resolvedSource.sourceBundlePath.path,
                        packageRoot: extensionRoot,
                        manifest: manifest,
                        operation: .safariEnable
                    )
                )

                await dependencies.activateInstallRuntime(
                    ExtensionInstallRuntimeActivationOwner.Request(
                        profileId: installProfileId,
                        extensionContext: extensionContext,
                        installedExtensionId: record.id,
                        operation: .safariEnable
                    )
                )
            } else {
                dependencies.ensureWebExtensionStorageDirectoryExists(extensionId)
            }

            if let beforePersist = dependencies.debugBeforePersistInstalledRecord() {
                try beforePersist(record)
            }
            try dependencies.persistRecord(record)
            await applyInstalledExtensionsMutationOnNextRunLoop { [dependencies] in
                dependencies.upsertInstalledExtension(record)
            }

            return record
        } catch {
            dependencies.tearDownExtensionRuntimeState(
                existingEntitySnapshot?.id ?? extensionId,
                false
            )
            if shouldRestoreExistingRuntime, let existingEntitySnapshot {
                do {
                    _ = try await loadEnabledExtension(from: existingEntitySnapshot)
                } catch let restoreError {
                    if let restoreProfileId = dependencies.fallbackProfileId() {
                        dependencies.logExtensionLoadFailure(
                            restoreError,
                            existingEntitySnapshot.id,
                            restoreProfileId,
                            "restore existing runtime after failed Safari extension enable"
                        )
                    } else {
                        ExtensionManager.logger.error(
                            "Failed to restore existing runtime after failed Safari extension enable for extension \(existingEntitySnapshot.id, privacy: .public): \(restoreError.localizedDescription, privacy: .public)"
                        )
                    }
                }
            }
            throw error
        }
    }
}

@available(macOS 15.5, *)
extension ExtensionInstallationFlowOwner.Dependencies {
    @MainActor
    static func live(manager: ExtensionManager) -> Self {
        Self(
            modelContext: manager.context,
            installationMetadataStore: manager.installationMetadataStore,
            isExtensionSupportAvailable: { [weak manager] in
                manager?.isExtensionSupportAvailable ?? false
            },
            extensionEntity: { [weak manager] extensionId in
                try manager?.extensionEntity(for: extensionId)
            },
            extensionResourcesRoot: { [weak manager] sourceKind, packagePath, sourceBundlePath in
                guard let manager else {
                    throw ExtensionError.installationFailed("Extension manager is unavailable")
                }
                return try manager.extensionResourcesRoot(
                    sourceKind: sourceKind,
                    packagePath: packagePath,
                    sourceBundlePath: sourceBundlePath
                )
            },
            refreshedRecord: { [weak manager] entity, manifest in
                guard let manager else {
                    throw ExtensionError.installationFailed("Extension manager is unavailable")
                }
                return try manager.refreshedRecord(for: entity, manifest: manifest)
            },
            upsertInstalledExtension: { [weak manager] record in
                manager?.upsertInstalledExtension(record)
            },
            installedExtensions: { [weak manager] in manager?.installedExtensions ?? [] },
            replaceInstalledExtension: { [weak manager] index, record in
                guard let manager, manager.installedExtensions.indices.contains(index) else { return }
                manager.installedExtensions[index] = record
            },
            removeInstalledExtension: { [weak manager] extensionId in
                manager?.installedExtensions.removeAll { $0.id == extensionId }
            },
            setInstalledExtensions: { [weak manager] records in
                manager?.installedExtensions = records
            },
            sortInstalledExtensions: { [weak manager] in manager?.sortInstalledExtensions() },
            reconcilePinnedToolbarExtensions: { [weak manager] in
                manager?.reconcilePinnedToolbarExtensions()
            },
            setExtensionsLoaded: { [weak manager] loaded in
                manager?.extensionsLoaded = loaded
            },
            fallbackProfileId: { [weak manager] in manager?.fallbackProfileId },
            resolvedProfileId: { [weak manager] explicitProfileId in
                manager?.resolvedProfileId(explicitProfileId: explicitProfileId)
            },
            ensureExtensionController: { [weak manager] profileId in
                _ = manager?.ensureExtensionController(for: profileId)
            },
            getExtensionContext: { [weak manager] extensionId, profileId in
                manager?.getExtensionContext(for: extensionId, profileId: profileId)
            },
            finalizeEnabledExtensionRuntime: { [weak manager] extensionId, profileId, reason in
                await manager?.finalizeEnabledExtensionRuntime(
                    for: extensionId,
                    profileId: profileId,
                    backgroundWakeReason: reason
                )
            },
            tearDownExtensionRuntimeState: { [weak manager] extensionId, removeUIState in
                manager?.tearDownExtensionRuntimeState(
                    for: extensionId,
                    removeUIState: removeUIState
                )
            },
            tearDownExtensionRuntime: { [weak manager] reason, removeUIState, releaseController in
                manager?.tearDownExtensionRuntime(
                    reason: reason,
                    removeUIState: removeUIState,
                    releaseController: releaseController
                )
            },
            hasEnabledInstalledExtensions: { [weak manager] in
                manager?.hasEnabledInstalledExtensions ?? false
            },
            removeStoredWebExtensionData: { [weak manager] extensionId, mode in
                await manager?.removeStoredWebExtensionData(for: extensionId, mode: mode)
            },
            hasStoredWebExtensionDataCandidate: { [weak manager] extensionId in
                manager?.hasStoredWebExtensionDataCandidate(for: extensionId) ?? false
            },
            traceWebExtensionStoreLifecycle: { [weak manager] phase, extensionId, manifest in
                manager?.traceWebExtensionStoreLifecycle(
                    phase: phase,
                    extensionId: extensionId,
                    manifest: manifest
                )
            },
            ensureWebExtensionStorageDirectoryExists: { [weak manager] extensionId in
                _ = manager?.ensureWebExtensionStorageDirectoryExists(for: extensionId)
            },
            requestExtensionRuntimeAndWait: { [weak manager] reason, allowWithoutEnabledExtensions in
                _ = await manager?.requestExtensionRuntimeAndWait(
                    reason: reason,
                    allowWithoutEnabledExtensions: allowWithoutEnabledExtensions
                )
            },
            resolveInstallSource: { sourceURL in
                try ExtensionInstallSourceResolver.resolve(at: sourceURL)
            },
            validateMV3Requirements: { manifest, baseURL in
                try ExtensionInstallSourceResolver.validateMV3Requirements(
                    manifest: manifest,
                    baseURL: baseURL
                )
            },
            // swiftlint:disable:next line_length
            makeInstalledRecord: { [weak manager] extensionId, manifest, extensionRoot, isEnabled, sourceKind, sourceBundlePath, sourceFingerprintURL, existingEntity in
                guard let manager else {
                    throw ExtensionError.installationFailed("Extension manager is unavailable")
                }
                return try manager.makeInstalledRecord(
                    extensionId: extensionId,
                    manifest: manifest,
                    extensionRoot: extensionRoot,
                    isEnabled: isEnabled,
                    sourceKind: sourceKind,
                    sourceBundlePath: sourceBundlePath,
                    sourceFingerprintURL: sourceFingerprintURL,
                    existingEntity: existingEntity
                )
            },
            persistRecord: { [weak manager] record in
                try manager?.persist(record: record)
            },
            updateEntity: { [weak manager] entity, record in
                manager?.update(entity, from: record)
            },
            extensionLoadGeneration: { [weak manager] in
                manager?.extensionLoadGeneration ?? 0
            },
            loadRuntimeContext: { [weak manager] request in
                guard let manager else {
                    throw ExtensionError.installationFailed("Extension manager is unavailable")
                }
                return try await ExtensionRuntimeContextLoadOwner(manager: manager).load(request)
            },
            activateInstallRuntime: { [weak manager] request in
                guard let manager else { return }
                await ExtensionInstallRuntimeActivationOwner(manager: manager).activate(request)
            },
            recordRuntimeMetric: { [weak manager] extensionId, update in
                manager?.runtimeSessionOwner.recordRuntimeMetric(for: extensionId, update: update)
            },
            clearExtensionLoadError: { [weak manager] extensionId, profileId in
                manager?.clearExtensionLoadError(extensionId: extensionId, profileId: profileId)
            },
            recordExtensionLoadError: { [weak manager] error, extensionId, profileId in
                manager?.recordExtensionLoadError(
                    error,
                    extensionId: extensionId,
                    profileId: profileId
                )
            },
            touchLiveExtensionContext: { [weak manager] extensionId, profileId in
                manager?.touchLiveExtensionContext(extensionId: extensionId, profileId: profileId)
            },
            enforceBoundedLiveExtensionContexts: { [weak manager] profileId, extensionId in
                manager?.enforceBoundedLiveExtensionContexts(
                    keepingProfileId: profileId,
                    keepingExtensionId: extensionId
                )
            },
            markExtensionRuntimeReadyIfProfileContextsLoaded: { [weak manager] profileId in
                manager?.markExtensionRuntimeReadyIfProfileContextsLoaded(for: profileId)
            },
            logExtensionLoadFailure: { [weak manager] error, extensionId, profileId, operation in
                manager?.logExtensionLoadFailure(
                    error,
                    extensionId: extensionId,
                    profileId: profileId,
                    operation: operation
                )
            },
            liveExtensionContextsCount: { [weak manager] in
                manager?.extensionContexts.count ?? 0
            },
            trace: { [weak manager] message in
                manager?.extensionRuntimeTrace(message)
            },
            debugBeforePersistInstalledRecord: { [weak manager] in
                #if DEBUG
                    manager?.testHooks.beforePersistInstalledRecord
                #else
                    nil
                #endif
            }
        )
    }
}

// MARK: - ExtensionManager facade

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func installExtension(
        from sourceURL: URL,
        completionHandler: @escaping (Result<InstalledExtension, ExtensionError>) -> Void
    ) {
        installationFlowOwner.installExtension(
            from: sourceURL,
            completionHandler: completionHandler
        )
    }

    func enableExtension(_ extensionId: String) async throws -> InstalledExtension {
        try await installationFlowOwner.enableExtension(extensionId)
    }

    func disableExtension(
        _ extensionId: String,
        releaseRuntimeIfIdle: Bool = true
    ) async throws {
        try await installationFlowOwner.disableExtension(
            extensionId,
            releaseRuntimeIfIdle: releaseRuntimeIfIdle
        )
    }

    func uninstallExtension(_ extensionId: String) async throws {
        try await installationFlowOwner.uninstallExtension(extensionId)
    }

    @discardableResult
    func loadInstalledExtensionMetadata() -> [ExtensionEntity] {
        installationFlowOwner.loadInstalledExtensionMetadata()
    }

    @discardableResult
    func applyInstalledExtensionMetadataLoadResult(
        _ result: ExtensionInstallationMetadataStore.MetadataLoadResult
    ) -> [ExtensionEntity] {
        installationFlowOwner.applyInstalledExtensionMetadataLoadResult(result)
    }

    func loadEnabledExtension(
        from entity: ExtensionEntity,
        profileId: UUID? = nil,
        expectedLoadGeneration: UInt64? = nil,
        postLoadBackgroundWakeReason: ExtensionBackgroundWakeReason? = nil
    ) async throws -> InstalledExtension {
        try await installationFlowOwner.loadEnabledExtension(
            from: entity,
            profileId: profileId,
            expectedLoadGeneration: expectedLoadGeneration,
            postLoadBackgroundWakeReason: postLoadBackgroundWakeReason
        )
    }

    func performInstallation(
        from sourceURL: URL,
        enableOnInstall: Bool = true
    ) async throws -> InstalledExtension {
        try await installationFlowOwner.performInstallation(
            from: sourceURL,
            enableOnInstall: enableOnInstall
        )
    }
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManager {
    func configureContextIdentity(
        _ extensionContext: WKWebExtensionContext,
        extensionId: String,
        profileId: UUID,
        sourceKind: WebExtensionSourceKind = .directory,
        sourceBundlePath: String? = nil
    ) {
        ExtensionRuntimeContextLoadOwner.configureContextIdentity(
            extensionContext,
            extensionId: extensionId,
            profileId: profileId,
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath
        )
    }
}
