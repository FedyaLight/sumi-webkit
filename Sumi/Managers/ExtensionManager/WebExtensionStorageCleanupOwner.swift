//
//  WebExtensionStorageCleanupOwner.swift
//  Sumi
//
//  Coordinates WebKit record deletion, storage snapshots, and diagnostics for
//  WebExtension cleanup. Install and runtime loading flows stay with
//  ExtensionManager+Installation.
//

import Foundation

@available(macOS 15.5, *)
@MainActor
final class WebExtensionStorageCleanupOwner {
    private let profileRuntime: ExtensionProfileRuntime
    private let installedExtensions: InstalledExtensionCollection
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let storageCleanupPlanner: WebExtensionStorageCleanupPlanner
    private let resolvedProfileID: @MainActor (UUID?) -> UUID?
    private let controllerStorageID: @MainActor (UUID) -> UUID
    #if DEBUG
        private var debugDataCleanup: (@MainActor ()
            -> (@MainActor (String) async -> Bool)?)?
    #endif

    init(
        profileRuntime: ExtensionProfileRuntime,
        installedExtensions: InstalledExtensionCollection,
        diagnostics: ExtensionRuntimeDiagnostics,
        storageCleanupPlanner: WebExtensionStorageCleanupPlanner,
        resolvedProfileID: @escaping @MainActor (UUID?) -> UUID?,
        controllerStorageID: @escaping @MainActor (UUID) -> UUID
    ) {
        self.profileRuntime = profileRuntime
        self.installedExtensions = installedExtensions
        self.diagnostics = diagnostics
        self.storageCleanupPlanner = storageCleanupPlanner
        self.resolvedProfileID = resolvedProfileID
        self.controllerStorageID = controllerStorageID
    }

    #if DEBUG
        func installDebugDataCleanup(
            _ provider: @escaping @MainActor ()
                -> (@MainActor (String) async -> Bool)?
        ) {
            debugDataCleanup = provider
        }
    #endif

    func removeStoredData(
        for extensionId: String,
        mode: ExtensionManager.WebExtensionStorageCleanupMode = .pruneDirectoryIfPossible
    ) async {
        traceLifecycle(
            phase: "cleanup-start",
            extensionId: extensionId
        )
        let hasDataCandidate = hasStoredDataCandidate(for: extensionId)
        if hasDataCandidate == false {
            finalizeCleanup(for: extensionId, mode: mode)
            traceLifecycle(
                phase: "cleanup-finished-no-local-candidate",
                extensionId: extensionId
            )
            if RuntimeDiagnostics.isVerboseEnabled {
                diagnostics.trace(
                    "Skipped WebExtension data cleanup for \(extensionId): no stored data candidate"
                )
            }
            return
        }

        #if DEBUG
            if let webExtensionDataCleanup = debugDataCleanup?(),
               await webExtensionDataCleanup(extensionId) {
                finalizeCleanup(for: extensionId, mode: mode)
                traceLifecycle(
                    phase: "cleanup-finished-test-hook",
                    extensionId: extensionId
                )
                return
            }
        #endif

        let dataCleanupOwner = WebExtensionControllerDataCleanupOwner()
        let matchingRecords = await dataCleanupOwner.matchingRecords(
            for: extensionId,
            controllersByProfile: profileRuntime.controllersByProfile,
            additionalUniqueIdentifiers: safariRuntimeIdentifiers(for: extensionId)
        )

        let preCleanupSnapshot = storageSnapshot(for: extensionId)

        guard matchingRecords.isEmpty == false else {
            finalizeCleanup(for: extensionId, mode: mode)
            traceLifecycle(
                phase: "cleanup-finished-no-controller-records",
                extensionId: extensionId
            )
            if RuntimeDiagnostics.isVerboseEnabled {
                diagnostics.trace(
                    "No stored WebExtension data found for \(extensionId)"
                )
            }
            return
        }

        await dataCleanupOwner.remove(
            matchingRecords,
            extensionId: extensionId,
            using: profileRuntime.controllersByProfile
        )

        let errors = matchingRecords.errors
        finalizeCleanup(for: extensionId, mode: mode)
        let postCleanupSnapshot = storageSnapshot(for: extensionId)
        let classifiedErrors = classifyCleanupErrors(
            errors,
            for: extensionId,
            preCleanupSnapshot: preCleanupSnapshot,
            postCleanupSnapshot: postCleanupSnapshot
        )
        if RuntimeDiagnostics.isVerboseEnabled {
            if errors.isEmpty {
                diagnostics.trace(
                    "Removed stored WebExtension data for \(extensionId)"
                )
            } else if classifiedErrors.actionableDiagnostics.isEmpty {
                diagnostics.trace(
                    "Removed stored WebExtension data for \(extensionId); ignored \(classifiedErrors.benignOptionalStoreDiagnostics.count) missing optional store errors"
                )
            } else {
                diagnostics.trace(
                    "Removed stored WebExtension data for \(extensionId) with \(classifiedErrors.actionableDiagnostics.count) actionable record errors"
                )
                let diagnosticsSummary = classifiedErrors.actionableDiagnostics.map(\.logSummary)
                    .joined(separator: " | ")
                diagnostics.trace(
                    "Actionable WebExtension cleanup diagnostics for \(extensionId): \(diagnosticsSummary)"
                )
            }
        }
        traceLifecycle(
            phase: "cleanup-finished",
            extensionId: extensionId
        )
    }

    /// Safari app extensions register their WebKit data under the composed
    /// "<bundleId> (<teamId>)" identifier (see `configureContextIdentity`), so
    /// cleanup must recognize that identifier in addition to the internal id.
    private func safariRuntimeIdentifiers(for extensionId: String) -> Set<String> {
        guard let installed = installedExtensions.records.first(where: {
            $0.id == extensionId
        }) else {
            return []
        }
        let identifier = SafariWebExtensionRuntimeIdentity.webKitStorageIdentifier(
            extensionId: extensionId,
            sourceKind: installed.sourceKind,
            sourceBundlePath: installed.sourceBundlePath
        )
        return identifier == extensionId ? [] : [identifier]
    }

    private func finalizeCleanup(
        for extensionId: String,
        mode: ExtensionManager.WebExtensionStorageCleanupMode
    ) {
        switch mode {
        case .pruneDirectoryIfPossible:
            _ = pruneEmptyOrStateOnlyStorageDirectory(for: extensionId)
        case .preserveDirectoryForImmediateRuntimeLoad:
            ensureStorageDirectoryExists(for: extensionId)
        }
    }

    private func storageCleanupStore(
        profileId: UUID? = nil
    ) -> WebExtensionStorageCleanupStore {
        let resolvedProfileId = resolvedProfileID(profileId)
        let controllerStorageId = resolvedProfileId.map {
            controllerStorageID($0)
        }
        return WebExtensionStorageCleanupStore(
            controllerStorageId: controllerStorageId,
            planner: storageCleanupPlanner,
            storageDirectoryNameResolver: { [installedExtensions] extensionId in
                guard let installed = installedExtensions.records.first(where: {
                          $0.id == extensionId
                      })
                else {
                    return extensionId
                }
                return SafariWebExtensionRuntimeIdentity.webKitStorageIdentifier(
                    extensionId: extensionId,
                    sourceKind: installed.sourceKind,
                    sourceBundlePath: installed.sourceBundlePath
                )
            }
        )
    }

    func hasStoredDataCandidate(for extensionId: String) -> Bool {
        storageCleanupStore().hasStoredDataCandidate(for: extensionId)
    }

    @discardableResult
    func pruneEmptyOrStateOnlyStorageDirectory(for extensionId: String) -> Bool {
        storageCleanupStore()
            .pruneEmptyOrStateOnlyDirectory(for: extensionId)
    }

    @discardableResult
    func ensureStorageDirectoryExists(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> Bool {
        storageCleanupStore(profileId: profileId)
            .ensureDirectoryExists(for: extensionId)
    }

    func storageSnapshot(
        for extensionId: String
    ) -> ExtensionManager.WebExtensionStorageSnapshot {
        storageCleanupStore().snapshot(for: extensionId)
    }

    func storeCapabilitySnapshot(
        for manifest: [String: Any]
    ) -> ExtensionManager.WebExtensionStoreCapabilitySnapshot {
        storageCleanupPlanner.storeCapabilitySnapshot(
            for: manifest,
            unsupportedAPIs: WebExtensionRuntimeCompatibilityPolicy
                .unsupportedAPIs(for: manifest)
        )
    }

    func classifyCleanupErrors(
        _ errors: [Error],
        for extensionId: String,
        preCleanupSnapshot: ExtensionManager.WebExtensionStorageSnapshot,
        postCleanupSnapshot: ExtensionManager.WebExtensionStorageSnapshot
    ) -> WebExtensionStorageCleanupPlanner.ErrorClassification {
        storageCleanupPlanner.classifyCleanupErrors(
            errors,
            extensionId: extensionId,
            preCleanupSnapshot: preCleanupSnapshot,
            postCleanupSnapshot: postCleanupSnapshot
        )
    }

    func traceLifecycle(
        phase: String,
        extensionId: String,
        manifest: [String: Any]? = nil
    ) {
        guard ExtensionManager.isWebKitRuntimeTraceEnabled else { return }
        let snapshot = storageSnapshot(for: extensionId)
        var message =
            "storeLifecycle phase=\(phase) extensionId=\(extensionId) directoryExists=\(snapshot.directoryExists) entries=\(snapshot.entryNames.joined(separator: ",")) registeredContentScripts=\(snapshot.hasRegisteredContentScriptsStore) localStorage=\(snapshot.hasLocalStorageStore) syncStorage=\(snapshot.hasSyncStorageStore) onlyPrunable=\(snapshot.hasOnlyPrunableEntries)"

        if let manifest {
            let capabilities = storeCapabilitySnapshot(for: manifest)
            message +=
                " webKitCompat=\(capabilities.usesWebKitCompatibilityPrelude) mayTouchDynamicContentScripts=\(capabilities.mayTouchDynamicContentScriptStore) mayTouchSyncStorage=\(capabilities.mayTouchSyncStorageStore) permissions=\(capabilities.declaredPermissions.joined(separator: ",")) unsupportedAPIs=\(capabilities.unsupportedAPIs.joined(separator: ","))"
        }

        diagnostics.trace(message)
    }
}
