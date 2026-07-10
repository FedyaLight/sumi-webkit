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
    private let manager: ExtensionManager
    private let storageCleanupPlanner: WebExtensionStorageCleanupPlanner

    init(
        manager: ExtensionManager,
        storageCleanupPlanner: WebExtensionStorageCleanupPlanner? = nil
    ) {
        self.manager = manager
        self.storageCleanupPlanner =
            storageCleanupPlanner ?? manager.webExtensionStorageCleanupPlanner
    }

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
                manager.runtimeDiagnostics.trace(
                    "Skipped WebExtension data cleanup for \(extensionId): no stored data candidate"
                )
            }
            return
        }

        #if DEBUG
            if let webExtensionDataCleanup = manager.testHooks.webExtensionDataCleanup,
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
            controllersByProfile: manager.profileRuntime.controllersByProfile,
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
                manager.runtimeDiagnostics.trace(
                    "No stored WebExtension data found for \(extensionId)"
                )
            }
            return
        }

        await dataCleanupOwner.remove(
            matchingRecords,
            extensionId: extensionId,
            using: manager.profileRuntime.controllersByProfile
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
                manager.runtimeDiagnostics.trace(
                    "Removed stored WebExtension data for \(extensionId)"
                )
            } else if classifiedErrors.actionableDiagnostics.isEmpty {
                manager.runtimeDiagnostics.trace(
                    "Removed stored WebExtension data for \(extensionId); ignored \(classifiedErrors.benignOptionalStoreDiagnostics.count) missing optional store errors"
                )
            } else {
                manager.runtimeDiagnostics.trace(
                    "Removed stored WebExtension data for \(extensionId) with \(classifiedErrors.actionableDiagnostics.count) actionable record errors"
                )
                let diagnosticsSummary = classifiedErrors.actionableDiagnostics.map(\.logSummary)
                    .joined(separator: " | ")
                manager.runtimeDiagnostics.trace(
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
        guard let installed = manager.installedExtensionCollection.records.first(where: {
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
        let resolvedProfileId =
            manager.resolvedProfileId(explicitProfileId: profileId)
        let controllerStorageId = resolvedProfileId.map {
            manager.extensionControllerIdentifier(for: $0)
        }
        return WebExtensionStorageCleanupStore(
            controllerStorageId: controllerStorageId,
            planner: storageCleanupPlanner,
            storageDirectoryNameResolver: { [weak manager] extensionId in
                guard let manager,
                      let installed = manager.installedExtensionCollection.records.first(where: {
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

    /// Adopts a legacy bare-id storage directory into the composed-identifier
    /// directory before the context loads, preserving extension state across
    /// the Safari runtime-identifier migration.
    ///
    /// The storage identity is resolved from the load request's source kind
    /// and bundle path — not from `installedExtensions`, which is empty during
    /// early startup loads and would silently turn adoption into a no-op.
    func adoptLegacyStorageDirectoryIfNeeded(
        for extensionId: String,
        profileId: UUID? = nil,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String?
    ) {
        let resolvedStorageName = SafariWebExtensionRuntimeIdentity.webKitStorageIdentifier(
            extensionId: extensionId,
            sourceKind: sourceKind,
            sourceBundlePath: sourceBundlePath
        )
        storageCleanupStore(profileId: profileId)
            .adoptLegacyStorageDirectoryIfNeeded(
                for: extensionId,
                resolvedStorageName: resolvedStorageName
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
        manager.installCapabilityOwner.webExtensionStoreCapabilitySnapshot(for: manifest)
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

        manager.runtimeDiagnostics.trace(message)
    }
}

@available(macOS 15.5, *)
extension ExtensionManager {
    func removeStoredWebExtensionData(
        for extensionId: String,
        mode: WebExtensionStorageCleanupMode = .pruneDirectoryIfPossible
    ) async {
        await WebExtensionStorageCleanupOwner(manager: self)
            .removeStoredData(for: extensionId, mode: mode)
    }

    func hasStoredWebExtensionDataCandidate(for extensionId: String) -> Bool {
        WebExtensionStorageCleanupOwner(manager: self)
            .hasStoredDataCandidate(for: extensionId)
    }

    @discardableResult
    func ensureWebExtensionStorageDirectoryExists(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> Bool {
        WebExtensionStorageCleanupOwner(manager: self)
            .ensureStorageDirectoryExists(for: extensionId, profileId: profileId)
    }

    func adoptLegacyWebExtensionStorageIfNeeded(
        for extensionId: String,
        profileId: UUID? = nil,
        sourceKind: WebExtensionSourceKind,
        sourceBundlePath: String?
    ) {
        WebExtensionStorageCleanupOwner(manager: self)
            .adoptLegacyStorageDirectoryIfNeeded(
                for: extensionId,
                profileId: profileId,
                sourceKind: sourceKind,
                sourceBundlePath: sourceBundlePath
            )
    }

    func webExtensionStorageSnapshot(
        for extensionId: String
    ) -> WebExtensionStorageSnapshot {
        WebExtensionStorageCleanupOwner(manager: self)
            .storageSnapshot(for: extensionId)
    }

    func traceWebExtensionStoreLifecycle(
        phase: String,
        extensionId: String,
        manifest: [String: Any]? = nil
    ) {
        WebExtensionStorageCleanupOwner(manager: self)
            .traceLifecycle(
                phase: phase,
                extensionId: extensionId,
                manifest: manifest
            )
    }
}
