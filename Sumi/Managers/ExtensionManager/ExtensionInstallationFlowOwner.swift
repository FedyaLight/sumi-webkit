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
        /// Records seam: CRUD over `ExtensionManager.installedExtensions`.
        let installedRecordsOwner: ExtensionInstalledRecordsOwner
        let toolbarPinningOwner: ExtensionToolbarPinningOwner
        let runtimeAccess: ExtensionFlowOwnerRuntimeAccess
        let runtimeLifecycleOwner: ExtensionRuntimeLifecycleOwner
        let runtimeStateResetOwner: ExtensionRuntimeStateResetOwner
        /// Full-runtime teardown needs the concrete manager instance
        /// (ExtensionRuntimeTeardownOwner.tearDownRuntime(manager:...)); no
        /// stored owner can absorb this without holding a strong `manager`.
        let tearDownExtensionRuntime: @MainActor (String, Bool, Bool) -> Void
        let actionSurfacePublicationOwner: ExtensionActionSurfacePublicationOwner
        let contextResidencyOwner: ExtensionContextResidencyOwner
        let runtimeDiagnosticsOwner: ExtensionRuntimeDiagnosticsOwner
        let isExtensionSupportAvailable: @MainActor () -> Bool
        let setExtensionsLoaded: @MainActor (Bool) -> Void
        let loadRuntimeContext: @MainActor (
            ExtensionRuntimeContextLoadOwner.Request
        ) async throws -> WKWebExtensionContext
        let activateInstallRuntime: @MainActor (
            ExtensionInstallRuntimeActivationOwner.Request
        ) async -> Void
        let removeStoredWebExtensionData: @MainActor (
            String, ExtensionManager.WebExtensionStorageCleanupMode
        ) async -> Void
        let hasStoredWebExtensionDataCandidate: @MainActor (String) -> Bool
        let traceWebExtensionStoreLifecycle: @MainActor (String, String, [String: Any]?) -> Void
        let ensureWebExtensionStorageDirectoryExists: @MainActor (String) -> Void
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

    // MARK: - Sibling-owner call shims
    //
    // These translate the pre-refactor closure call shape onto the owner
    // references now held in `Dependencies`, so the flow methods below read
    // the same as before while the seam narrows to real collaborators.

    private func extensionEntity(_ extensionId: String) throws -> ExtensionEntity? {
        try dependencies.installationMetadataStore.extensionEntity(for: extensionId)
    }

    private func extensionResourcesRoot(
        _ sourceKind: WebExtensionSourceKind,
        _ packagePath: String,
        _ sourceBundlePath: String
    ) throws -> URL {
        try dependencies.installationMetadataStore.extensionResourcesRoot(
            sourceKind: sourceKind,
            packagePath: packagePath,
            sourceBundlePath: sourceBundlePath
        )
    }

    private func refreshedRecord(
        _ entity: ExtensionEntity,
        _ manifest: [String: Any]
    ) throws -> InstalledExtension {
        try dependencies.installationMetadataStore.refreshedRecord(for: entity, manifest: manifest)
    }

    private func makeInstalledRecord(
        _ extensionId: String,
        _ manifest: [String: Any],
        _ extensionRoot: URL,
        _ isEnabled: Bool,
        _ sourceKind: WebExtensionSourceKind,
        _ sourceBundlePath: String,
        _ sourceFingerprintURL: URL,
        _ existingEntity: ExtensionEntity?
    ) throws -> InstalledExtension {
        try dependencies.installationMetadataStore.makeInstalledRecord(
            extensionId: extensionId,
            manifest: manifest,
            extensionRoot: extensionRoot,
            isEnabled: isEnabled,
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath,
            sourceFingerprintURL: sourceFingerprintURL,
            existingEntity: existingEntity
        )
    }

    private func persistRecord(_ record: InstalledExtension) throws {
        try dependencies.installationMetadataStore.persist(record: record)
    }

    private func updateEntity(_ entity: ExtensionEntity, _ record: InstalledExtension) {
        dependencies.installationMetadataStore.update(entity, from: record)
    }

    private func setInstalledExtensions(_ records: [InstalledExtension]) {
        dependencies.installedRecordsOwner.setAll(records)
    }

    private func hasEnabledInstalledExtensions() -> Bool {
        dependencies.installedRecordsOwner.records.contains { $0.isEnabled }
    }

    private func reconcilePinnedToolbarExtensions() {
        dependencies.toolbarPinningOwner.reconcilePinnedToolbarExtensions()
    }

    private func fallbackProfileId() -> UUID? {
        dependencies.runtimeAccess.fallbackProfileId()
    }

    private func resolvedProfileId(_ explicitProfileId: UUID?) -> UUID? {
        dependencies.runtimeAccess.resolvedProfileId(explicitProfileId)
    }

    private func ensureExtensionController(_ profileId: UUID) {
        dependencies.runtimeAccess.ensureExtensionController(profileId)
    }

    private func getExtensionContext(
        _ extensionId: String,
        _ profileId: UUID
    ) -> WKWebExtensionContext? {
        dependencies.runtimeAccess.getExtensionContext(extensionId, profileId)
    }

    private func liveExtensionContextsCount() -> Int {
        dependencies.runtimeAccess.profileRuntimeOwner.contextsForCurrentProfile().count
    }

    private func finalizeEnabledExtensionRuntime(
        _ extensionId: String,
        _ profileId: UUID,
        _ backgroundWakeReason: ExtensionManager.ExtensionBackgroundWakeReason?
    ) async {
        await dependencies.actionSurfacePublicationOwner.finalizeEnabledExtensionRuntime(
            for: extensionId,
            profileId: profileId,
            backgroundWakeReason: backgroundWakeReason
        )
    }

    private func tearDownExtensionRuntimeState(_ extensionId: String, _ removeUIState: Bool) {
        dependencies.runtimeStateResetOwner.tearDownExtensionRuntimeState(
            for: extensionId,
            removeUIState: removeUIState
        )
    }

    private func requestExtensionRuntimeAndWait(
        _ reason: ExtensionManager.ExtensionRuntimeRequestReason,
        _ allowWithoutEnabledExtensions: Bool
    ) async {
        _ = await dependencies.runtimeLifecycleOwner.requestExtensionRuntimeAndWait(
            reason: reason,
            allowWithoutEnabledExtensions: allowWithoutEnabledExtensions
        )
    }

    private func extensionLoadGeneration() -> UInt64 {
        dependencies.runtimeAccess.runtimeSessionOwner.extensionLoadGeneration
    }

    private func recordRuntimeMetric(
        _ extensionId: String,
        _ update: (inout ExtensionManager.ExtensionRuntimeMetrics) -> Void
    ) {
        dependencies.runtimeAccess.runtimeSessionOwner.recordRuntimeMetric(
            for: extensionId,
            update: update
        )
    }

    private func clearExtensionLoadError(_ extensionId: String, _ profileId: UUID) {
        dependencies.runtimeAccess.clearExtensionLoadError(extensionId, profileId)
    }

    private func recordExtensionLoadError(_ error: Error, _ extensionId: String, _ profileId: UUID) {
        dependencies.runtimeAccess.recordExtensionLoadError(error, extensionId, profileId)
    }

    private func touchLiveExtensionContext(_ extensionId: String, _ profileId: UUID) {
        dependencies.contextResidencyOwner.touchLiveExtensionContext(
            extensionId: extensionId,
            profileId: profileId
        )
    }

    private func enforceBoundedLiveExtensionContexts(_ profileId: UUID, _ extensionId: String) {
        dependencies.contextResidencyOwner.enforceBoundedLiveExtensionContexts(
            keepingProfileId: profileId,
            keepingExtensionId: extensionId
        )
    }

    private func markExtensionRuntimeReadyIfProfileContextsLoaded(_ profileId: UUID) {
        dependencies.contextResidencyOwner.markExtensionRuntimeReadyIfProfileContextsLoaded(
            for: profileId
        )
    }

    private func logExtensionLoadFailure(
        _ error: Error,
        _ extensionId: String,
        _ profileId: UUID,
        _ operation: String
    ) {
        ExtensionManager.logger.error(
            "Failed to \(operation, privacy: .public) for extension \(extensionId, privacy: .public) profile \(profileId.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
        )
    }

    private func trace(_ message: @autoclosure () -> String) {
        guard ExtensionManager.isWebKitRuntimeTraceEnabled else { return }
        dependencies.runtimeDiagnosticsOwner.trace(message())
    }

    private func resolveInstallSource(
        _ sourceURL: URL
    ) throws -> ExtensionInstallSourceResolver.ResolvedInstallSource {
        try ExtensionInstallSourceResolver.resolve(at: sourceURL)
    }

    private func validateMV3Requirements(_ manifest: [String: Any], _ baseURL: URL) throws {
        try ExtensionInstallSourceResolver.validateMV3Requirements(
            manifest: manifest,
            baseURL: baseURL
        )
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
        guard let entity = try extensionEntity(extensionId) else {
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
        let extensionRoot = try extensionResourcesRoot(
            sourceKind,
            entity.packagePath,
            entity.sourceBundlePath
        )
        let manifest = try ExtensionUtils.validateManifest(
            at: extensionRoot.appendingPathComponent("manifest.json"),
            policy: WebExtensionManifestValidationPolicy.forSourceKind(sourceKind)
        )
        let refreshed = try refreshedRecord(entity, manifest)
        await applyInstalledExtensionsMutationOnNextRunLoop { [recordsOwner = dependencies.installedRecordsOwner] in
            recordsOwner.upsert(refreshed)
        }
        loadInstalledExtensionMetadata()

        let enableProfileId = fallbackProfileId()
        guard let enableProfileId else {
            throw ExtensionError.installationFailed(
                "Extension runtime profile is unavailable"
            )
        }

        ensureExtensionController(enableProfileId)
        if getExtensionContext(extensionId, enableProfileId) == nil {
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
        tearDownExtensionRuntimeState(extensionId, true)

        if let entity = try extensionEntity(extensionId) {
            try dependencies.installationMetadataStore.setEnabled(false, for: entity)
        }

        await applyInstalledExtensionsMutationOnNextRunLoop { [
            recordsOwner = dependencies.installedRecordsOwner,
            metadataStore = dependencies.installationMetadataStore
        ] in
            guard let index = recordsOwner.records
                .firstIndex(where: { $0.id == extensionId })
            else {
                return
            }

            let current = recordsOwner.records[index]
            let updated = metadataStore.record(
                current,
                withEnabledState: false
            )
            recordsOwner.replace(at: index, with: updated)
            recordsOwner.sort()
        }

        if releaseRuntimeIfIdle && hasEnabledInstalledExtensions() == false {
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

        if let entity = try extensionEntity(extensionId) {
            let sourceKind = WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            let packageURL = URL(fileURLWithPath: entity.packagePath, isDirectory: true)
            if sourceKind == .directory,
               FileManager.default.fileExists(atPath: packageURL.path) {
                try FileManager.default.removeItem(at: packageURL)
            }
            dependencies.modelContext.delete(entity)
            try dependencies.modelContext.save()
        }

        await applyInstalledExtensionsMutationOnNextRunLoop { [recordsOwner = dependencies.installedRecordsOwner] in
            recordsOwner.remove(id: extensionId)
        }

        if hasEnabledInstalledExtensions() == false {
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

        trace(
            "loadInstalledExtensionMetadata start installedContexts=\(liveExtensionContextsCount())"
        )

        let result = dependencies.installationMetadataStore.loadInstalledExtensionMetadata {
            trace($0)
        }
        return applyInstalledExtensionMetadataLoadResult(result)
    }

    @discardableResult
    func applyInstalledExtensionMetadataLoadResult(
        _ result: ExtensionInstallationMetadataStore.MetadataLoadResult
    ) -> [ExtensionEntity] {
        setInstalledExtensions(result.records)
        if result.didFetchPersistedMetadata {
            reconcilePinnedToolbarExtensions()
        }
        dependencies.setExtensionsLoaded(true)
        trace(
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
        let loadGeneration = expectedLoadGeneration ?? extensionLoadGeneration()
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.loadEnabledExtension")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.loadEnabledExtension", signpostState)
        }

        do {
            let resolvedProfileId = resolvedProfileId(profileId)
            guard let resolvedProfileId else {
                throw ExtensionError.installationFailed(
                    "Extension runtime profile is unavailable"
                )
            }
            let sourceKind =
                WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            let extensionRoot = try extensionResourcesRoot(
                sourceKind,
                entity.packagePath,
                entity.sourceBundlePath
            )
            let manifestURL = extensionRoot.appendingPathComponent("manifest.json")
            trace(
                "loadEnabledExtension start extensionId=\(entity.id) profileId=\(resolvedProfileId.uuidString) expectedGeneration=\(loadGeneration) currentGeneration=\(extensionLoadGeneration()) packagePath=\(extensionRoot.path)"
            )
            let validationStart = CFAbsoluteTimeGetCurrent()
            let manifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: WebExtensionManifestValidationPolicy.forSourceKind(sourceKind)
            )
            recordRuntimeMetric(entity.id) {
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

            clearExtensionLoadError(entity.id, resolvedProfileId)
            touchLiveExtensionContext(entity.id, resolvedProfileId)
            enforceBoundedLiveExtensionContexts(resolvedProfileId, entity.id)

            await finalizeLoadedEnabledExtensionRuntime(
                entity.id,
                resolvedProfileId,
                extensionContext: extensionContext,
                activation: postLoadActivation
            )

            let refreshed = try refreshedRecord(entity, manifest)
            await applyInstalledExtensionsMutationOnNextRunLoop { [recordsOwner = dependencies.installedRecordsOwner] in
                recordsOwner.upsert(refreshed)
            }
            updateEntity(entity, refreshed)
            try dependencies.modelContext.save()
            return refreshed
        } catch {
            let errorProfileId = resolvedProfileId(profileId)
            if let errorProfileId {
                recordExtensionLoadError(error, entity.id, errorProfileId)
            }
            tearDownExtensionRuntimeState(entity.id, false)
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
        guard let extensionContext = getExtensionContext(
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
            await finalizeEnabledExtensionRuntime(
                extensionId,
                profileId,
                backgroundWakeReason
            )
            markExtensionRuntimeReadyIfProfileContextsLoaded(profileId)
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
            await requestExtensionRuntimeAndWait(.install, true)
        }

        let resolvedSource = try resolveInstallSource(sourceURL)
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
            try validateMV3Requirements(manifest, temporaryDirectory)

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
            existingEntitySnapshot = try extensionEntity(extensionId)
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
                tearDownExtensionRuntimeState(existingEntitySnapshot.id, false)
            } else if resolvedSource.sourceKind == .safariAppExtension {
                // Safari parity: reinstalling a Safari app extension keeps its
                // WebKit data — Safari preserves extension state across
                // reinstall and containing-app updates.
                if RuntimeDiagnostics.isVerboseEnabled {
                    trace(
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
                    trace(
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

            let record = try makeInstalledRecord(
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
                let installProfileId = fallbackProfileId()
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
            try persistRecord(record)
            await applyInstalledExtensionsMutationOnNextRunLoop { [recordsOwner = dependencies.installedRecordsOwner] in
                recordsOwner.upsert(record)
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
                tearDownExtensionRuntimeState(installedExtensionID, false)
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
                    if let restoreProfileId = fallbackProfileId() {
                        logExtensionLoadFailure(
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
        try validateMV3Requirements(manifest, extensionRoot)

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
            existingEntitySnapshot = try extensionEntity(extensionId)
        }
        let shouldRestoreExistingRuntime = existingEntitySnapshot?.isEnabled == true

        do {
            if let existingEntitySnapshot {
                tearDownExtensionRuntimeState(existingEntitySnapshot.id, false)
            }
            // Safari parity: reinstalling or updating a Safari app extension
            // keeps its WebKit data (sessions survive extension updates in
            // Safari). Stale-data cleanup applies only to directory sources.

            let record = try makeInstalledRecord(
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
                let installProfileId = fallbackProfileId()
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
            try persistRecord(record)
            await applyInstalledExtensionsMutationOnNextRunLoop { [recordsOwner = dependencies.installedRecordsOwner] in
                recordsOwner.upsert(record)
            }

            return record
        } catch {
            tearDownExtensionRuntimeState(
                existingEntitySnapshot?.id ?? extensionId,
                false
            )
            if shouldRestoreExistingRuntime, let existingEntitySnapshot {
                do {
                    _ = try await loadEnabledExtension(from: existingEntitySnapshot)
                } catch let restoreError {
                    if let restoreProfileId = fallbackProfileId() {
                        logExtensionLoadFailure(
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
            installedRecordsOwner: manager.installedRecordsOwner,
            toolbarPinningOwner: manager.toolbarPinningOwner,
            runtimeAccess: ExtensionFlowOwnerRuntimeAccess(
                profileRuntimeOwner: manager.profileRuntimeOwner,
                controllerProvisioningOwner: manager.controllerProvisioningOwner,
                runtimeSessionOwner: manager.runtimeSessionOwner,
                runtime: { [weak manager] in manager?.runtime ?? .inactive }
            ),
            runtimeLifecycleOwner: manager.runtimeLifecycleOwner,
            runtimeStateResetOwner: manager.runtimeStateResetOwner,
            tearDownExtensionRuntime: { [weak manager] reason, removeUIState, releaseController in
                manager?.tearDownExtensionRuntime(
                    reason: reason,
                    removeUIState: removeUIState,
                    releaseController: releaseController
                )
            },
            actionSurfacePublicationOwner: manager.actionSurfacePublicationOwner,
            contextResidencyOwner: manager.contextResidencyOwner,
            runtimeDiagnosticsOwner: manager.runtimeDiagnosticsOwner,
            isExtensionSupportAvailable: { [weak manager] in
                manager?.isExtensionSupportAvailable ?? false
            },
            setExtensionsLoaded: { [weak manager] loaded in
                manager?.extensionsLoaded = loaded
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
