import Foundation
import SwiftData
import WebKit

/// Loads one persisted extension into a profile-scoped WebKit runtime.
/// Package replacement and enablement persistence are separate transactions.
@available(macOS 15.5, *)
@MainActor
final class ExtensionRuntimeLoader {
    enum EnableActivation {
        case background(ExtensionManager.ExtensionBackgroundWakeReason?)
        case safariAppExtension

        func loadOperation(
            expectedGeneration: UInt64
        ) -> ExtensionRuntimeContextLoader.Operation {
            switch self {
            case .background:
                return .loadEnabled(expectedGeneration: expectedGeneration)
            case .safariAppExtension:
                return .safariEnable
            }
        }
    }

    enum InstallationOperation {
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

    struct Environment {
        let modelContext: ModelContext
        let metadataStore: ExtensionInstallationMetadataStore
        let installedRecords: InstalledExtensionCollection
        let runtimeAccess: ExtensionRuntimeAccess
        let resetRuntimeState: @MainActor (String, Bool) -> Void
        let finalizeBackgroundRuntime: @MainActor (
            String, UUID, ExtensionManager.ExtensionBackgroundWakeReason?
        ) async -> Void
        let touchContext: @MainActor (String, UUID) -> Void
        let boundContextCount: @MainActor (UUID, String) -> Void
        let markProfileRuntimeReady: @MainActor (UUID) -> Void
        let loadContext: @MainActor (ExtensionRuntimeContextLoader.Request) async throws
            -> WKWebExtensionContext
        let activateInstalledRuntime: @MainActor (ExtensionInstallRuntimeActivator.Request)
            async -> Void
        let trace: @MainActor (String) -> Void
    }

    private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    func resolvedProfileID(_ explicitProfileID: UUID? = nil) -> UUID? {
        environment.runtimeAccess.resolvedProfileId(explicitProfileID)
    }

    func ensureController(for profileID: UUID) {
        environment.runtimeAccess.ensureExtensionController(profileID)
    }

    func hasLoadedContext(extensionID: String, profileID: UUID) -> Bool {
        environment.runtimeAccess.getExtensionContext(extensionID, profileID) != nil
    }

    func resetRuntimeState(extensionID: String, removeUIState: Bool) {
        environment.resetRuntimeState(extensionID, removeUIState)
    }

    func loadEnabled(
        from entity: ExtensionEntity,
        profileID: UUID? = nil,
        expectedLoadGeneration: UInt64? = nil,
        postLoadBackgroundWakeReason: ExtensionManager.ExtensionBackgroundWakeReason? = nil
    ) async throws -> InstalledExtension {
        try await loadEnabled(
            from: entity,
            profileID: profileID,
            expectedLoadGeneration: expectedLoadGeneration,
            activation: .background(postLoadBackgroundWakeReason)
        )
    }

    func loadEnabled(
        from entity: ExtensionEntity,
        profileID: UUID? = nil,
        expectedLoadGeneration: UInt64? = nil,
        activation: EnableActivation
    ) async throws -> InstalledExtension {
        let loadGeneration =
            expectedLoadGeneration
            ?? environment.runtimeAccess.runtimeSession.extensionLoadGeneration
        let signpostState = PerformanceTrace.beginInterval("ExtensionManager.loadEnabledExtension")
        defer {
            PerformanceTrace.endInterval("ExtensionManager.loadEnabledExtension", signpostState)
        }

        do {
            guard let resolvedProfileID = resolvedProfileID(profileID) else {
                throw ExtensionError.installationFailed(
                    "Extension runtime profile is unavailable"
                )
            }
            let sourceKind =
                WebExtensionSourceKind(rawValue: entity.sourceKindRawValue) ?? .directory
            let extensionRoot = try environment.metadataStore.extensionResourcesRoot(
                sourceKind: sourceKind,
                packagePath: entity.packagePath,
                sourceBundlePath: entity.sourceBundlePath
            )
            let manifestURL = extensionRoot.appendingPathComponent("manifest.json")
            trace(
                "loadEnabledExtension start extensionId=\(entity.id) profileId=\(resolvedProfileID.uuidString) expectedGeneration=\(loadGeneration) currentGeneration=\(environment.runtimeAccess.runtimeSession.extensionLoadGeneration) packagePath=\(extensionRoot.path)"
            )
            let validationStart = CFAbsoluteTimeGetCurrent()
            let manifest = try ExtensionUtils.validateManifest(
                at: manifestURL,
                policy: WebExtensionManifestValidationPolicy.forSourceKind(sourceKind)
            )
            environment.runtimeAccess.runtimeSession.recordRuntimeMetric(for: entity.id) {
                $0.manifestValidationDuration = CFAbsoluteTimeGetCurrent() - validationStart
            }

            let extensionContext = try await environment.loadContext(
                ExtensionRuntimeContextLoader.Request(
                    extensionId: entity.id,
                    profileId: resolvedProfileID,
                    sourceKind: sourceKind,
                    sourceBundlePath: entity.sourceBundlePath,
                    packageRoot: extensionRoot,
                    manifest: manifest,
                    operation: activation.loadOperation(expectedGeneration: loadGeneration)
                )
            )

            environment.runtimeAccess.clearExtensionLoadError(entity.id, resolvedProfileID)
            environment.touchContext(entity.id, resolvedProfileID)
            environment.boundContextCount(resolvedProfileID, entity.id)
            await finalizeLoadedRuntime(
                extensionID: entity.id,
                profileID: resolvedProfileID,
                context: extensionContext,
                activation: activation
            )

            let refreshed = try environment.metadataStore.refreshedRecord(
                for: entity,
                manifest: manifest
            )
            await publishRecord(refreshed)
            environment.metadataStore.update(entity, from: refreshed)
            try environment.modelContext.save()
            return refreshed
        } catch {
            if let errorProfileID = resolvedProfileID(profileID) {
                environment.runtimeAccess.recordExtensionLoadError(
                    error,
                    entity.id,
                    errorProfileID
                )
            }
            environment.resetRuntimeState(entity.id, false)
            throw error
        }
    }

    func finalizeAlreadyLoadedRuntime(
        extensionID: String,
        profileID: UUID,
        activation: EnableActivation
    ) async {
        guard let context = environment.runtimeAccess.getExtensionContext(
            extensionID,
            profileID
        ) else {
            return
        }
        await finalizeLoadedRuntime(
            extensionID: extensionID,
            profileID: profileID,
            context: context,
            activation: activation
        )
    }

    func activateInstalledExtension(
        extensionID: String,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String,
        packageRoot: URL,
        manifest: [String: Any],
        operation: InstallationOperation
    ) async throws {
        guard let profileID = resolvedProfileID() else {
            throw ExtensionError.installationFailed(
                "Extension runtime profile is unavailable"
            )
        }
        let context = try await environment.loadContext(
            ExtensionRuntimeContextLoader.Request(
                extensionId: extensionID,
                profileId: profileID,
                sourceKind: sourceKind,
                sourceBundlePath: sourceBundlePath,
                packageRoot: packageRoot,
                manifest: manifest,
                operation: operation.contextLoadOperation
            )
        )
        await environment.activateInstalledRuntime(
            ExtensionInstallRuntimeActivator.Request(
                profileId: profileID,
                extensionContext: context,
                installedExtensionId: extensionID,
                operation: operation.activationOperation
            )
        )
    }

    func restoreEnabledRuntime(
        from entity: ExtensionEntity,
        after operation: String
    ) async {
        do {
            _ = try await loadEnabled(from: entity)
        } catch {
            if let profileID = resolvedProfileID() {
                ExtensionManager.logger.error(
                    "Failed to \(operation, privacy: .public) for extension \(entity.id, privacy: .public) profile \(profileID.uuidString, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            } else {
                ExtensionManager.logger.error(
                    "Failed to \(operation, privacy: .public) for extension \(entity.id, privacy: .public): \(error.localizedDescription, privacy: .public)"
                )
            }
        }
    }

    private func finalizeLoadedRuntime(
        extensionID: String,
        profileID: UUID,
        context: WKWebExtensionContext,
        activation: EnableActivation
    ) async {
        switch activation {
        case .background(let wakeReason):
            await environment.finalizeBackgroundRuntime(
                extensionID,
                profileID,
                wakeReason
            )
            environment.markProfileRuntimeReady(profileID)
        case .safariAppExtension:
            await environment.activateInstalledRuntime(
                ExtensionInstallRuntimeActivator.Request(
                    profileId: profileID,
                    extensionContext: context,
                    installedExtensionId: extensionID,
                    operation: .safariEnable
                )
            )
        }
    }

    private func publishRecord(_ record: InstalledExtension) async {
        await withCheckedContinuation { continuation in
            Task { @MainActor [installedRecords = environment.installedRecords] in
                await Task.yield()
                installedRecords.upsert(record)
                continuation.resume(returning: ())
            }
        }
    }

    private func trace(_ message: @autoclosure () -> String) {
        guard ExtensionManager.isWebKitRuntimeTraceEnabled else { return }
        environment.trace(message())
    }
}

@available(macOS 15.5, *)
extension ExtensionRuntimeLoader.Environment {
    @MainActor
    static func makeLive(manager: ExtensionManager) -> Self {
        Self(
            modelContext: manager.context,
            metadataStore: manager.installationMetadataStore,
            installedRecords: manager.installedExtensionCollection,
            runtimeAccess: ExtensionRuntimeAccess(
                profileRuntime: manager.profileRuntime,
                controllerProvisioningOwner: manager.controllerProvisioningOwner,
                runtimeSession: manager.runtimeSession,
                runtime: { [weak manager] in manager?.runtime ?? .inactive }
            ),
            resetRuntimeState: { [weak manager] extensionID, removeUIState in
                manager?.runtimeStateResetOwner.tearDownExtensionRuntimeState(
                    for: extensionID,
                    removeUIState: removeUIState
                )
            },
            finalizeBackgroundRuntime: { [weak manager] extensionID, profileID, wakeReason in
                await manager?.actionSurfacePublisher.finalizeEnabledExtensionRuntime(
                    for: extensionID,
                    profileId: profileID,
                    backgroundWakeReason: wakeReason
                )
            },
            touchContext: { [weak manager] extensionID, profileID in
                manager?.contextResidencyOwner.touchLiveExtensionContext(
                    extensionId: extensionID,
                    profileId: profileID
                )
            },
            boundContextCount: { [weak manager] profileID, extensionID in
                manager?.contextResidencyOwner.enforceBoundedLiveExtensionContexts(
                    keepingProfileId: profileID,
                    keepingExtensionId: extensionID
                )
            },
            markProfileRuntimeReady: { [weak manager] profileID in
                manager?.contextResidencyOwner.markExtensionRuntimeReadyIfProfileContextsLoaded(
                    for: profileID
                )
            },
            loadContext: { [weak manager] request in
                guard let manager else {
                    throw ExtensionError.installationFailed("Extension manager is unavailable")
                }
                return try await ExtensionRuntimeContextLoader(manager: manager).load(request)
            },
            activateInstalledRuntime: { [weak manager] request in
                guard let manager else { return }
                await ExtensionInstallRuntimeActivator(manager: manager).activate(request)
            },
            trace: { [weak manager] message in manager?.runtimeDiagnostics.trace(message) }
        )
    }
}
