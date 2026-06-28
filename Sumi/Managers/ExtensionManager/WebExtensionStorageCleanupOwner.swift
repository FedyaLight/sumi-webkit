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

    init(manager: ExtensionManager) {
        self.manager = manager
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
                manager.extensionRuntimeTrace(
                    "Skipped WebExtension data cleanup for \(extensionId): no stored data candidate"
                )
            }
            return
        }

        #if DEBUG
            if let webExtensionDataCleanup = manager.testHooks.webExtensionDataCleanup,
               await webExtensionDataCleanup(extensionId)
            {
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
            controllersByProfile: manager.extensionControllersByProfile
        )

        let preCleanupSnapshot = storageSnapshot(for: extensionId)

        guard matchingRecords.isEmpty == false else {
            finalizeCleanup(for: extensionId, mode: mode)
            traceLifecycle(
                phase: "cleanup-finished-no-controller-records",
                extensionId: extensionId
            )
            if RuntimeDiagnostics.isVerboseEnabled {
                manager.extensionRuntimeTrace(
                    "No stored WebExtension data found for \(extensionId)"
                )
            }
            return
        }

        await dataCleanupOwner.remove(
            matchingRecords,
            extensionId: extensionId,
            using: manager.extensionControllersByProfile
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
                manager.extensionRuntimeTrace(
                    "Removed stored WebExtension data for \(extensionId)"
                )
            } else if classifiedErrors.actionableDiagnostics.isEmpty {
                manager.extensionRuntimeTrace(
                    "Removed stored WebExtension data for \(extensionId); ignored \(classifiedErrors.benignOptionalStoreDiagnostics.count) missing optional store errors"
                )
            } else {
                manager.extensionRuntimeTrace(
                    "Removed stored WebExtension data for \(extensionId) with \(classifiedErrors.actionableDiagnostics.count) actionable record errors"
                )
                let diagnosticsSummary = classifiedErrors.actionableDiagnostics.map(\.logSummary)
                    .joined(separator: " | ")
                manager.extensionRuntimeTrace(
                    "Actionable WebExtension cleanup diagnostics for \(extensionId): \(diagnosticsSummary)"
                )
            }
        }
        traceLifecycle(
            phase: "cleanup-finished",
            extensionId: extensionId
        )
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
            profileId ?? manager.currentProfileId ?? manager.browserManager?.currentProfile?.id
        let controllerStorageId = resolvedProfileId.map {
            manager.extensionControllerIdentifier(for: $0)
        }
        return WebExtensionStorageCleanupStore(controllerStorageId: controllerStorageId)
    }

    func hasStoredDataCandidate(for extensionId: String) -> Bool {
        storageCleanupStore().hasStoredDataCandidate(for: extensionId)
    }

    @discardableResult
    func pruneEmptyOrStateOnlyStorageDirectory(for extensionId: String) -> Bool {
        storageCleanupStore()
            .pruneEmptyOrStateOnlyDirectory(for: extensionId)
    }

    func storageDirectory(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> URL? {
        storageCleanupStore(profileId: profileId)
            .directory(for: extensionId)
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
    ) -> ExtensionManager.WebExtensionCleanupErrorClassification {
        WebExtensionStorageCleanupPlanner.shared.classifyCleanupErrors(
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

        manager.extensionRuntimeTrace(message)
    }

    func makeCleanupErrorDiagnostic(
        _ error: Error
    ) -> ExtensionManager.WebExtensionCleanupErrorDiagnostic {
        WebExtensionStorageCleanupPlanner.shared.makeErrorDiagnostic(error)
    }

    func isBenignMissingOptionalStoreError(
        _ diagnostic: ExtensionManager.WebExtensionCleanupErrorDiagnostic,
        extensionId: String,
        preCleanupSnapshot: ExtensionManager.WebExtensionStorageSnapshot,
        postCleanupSnapshot: ExtensionManager.WebExtensionStorageSnapshot,
        hasNonOptionalFailureSignals: Bool
    ) -> Bool {
        WebExtensionStorageCleanupPlanner.shared.isBenignMissingOptionalStoreError(
            diagnostic,
            extensionId: extensionId,
            preCleanupSnapshot: preCleanupSnapshot,
            postCleanupSnapshot: postCleanupSnapshot,
            hasNonOptionalFailureSignals: hasNonOptionalFailureSignals
        )
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
    func pruneEmptyOrStateOnlyWebExtensionStorageDirectory(for extensionId: String) -> Bool {
        WebExtensionStorageCleanupOwner(manager: self)
            .pruneEmptyOrStateOnlyStorageDirectory(for: extensionId)
    }

    func webExtensionStorageDirectory(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> URL? {
        WebExtensionStorageCleanupOwner(manager: self)
            .storageDirectory(for: extensionId, profileId: profileId)
    }

    @discardableResult
    func ensureWebExtensionStorageDirectoryExists(
        for extensionId: String,
        profileId: UUID? = nil
    ) -> Bool {
        WebExtensionStorageCleanupOwner(manager: self)
            .ensureStorageDirectoryExists(for: extensionId, profileId: profileId)
    }

    func webExtensionStorageSnapshot(
        for extensionId: String
    ) -> WebExtensionStorageSnapshot {
        WebExtensionStorageCleanupOwner(manager: self)
            .storageSnapshot(for: extensionId)
    }

    func webExtensionStoreCapabilitySnapshot(
        for manifest: [String: Any]
    ) -> WebExtensionStoreCapabilitySnapshot {
        WebExtensionStorageCleanupOwner(manager: self)
            .storeCapabilitySnapshot(for: manifest)
    }

    func classifyWebExtensionDataCleanupErrors(
        _ errors: [Error],
        for extensionId: String,
        preCleanupSnapshot: WebExtensionStorageSnapshot,
        postCleanupSnapshot: WebExtensionStorageSnapshot
    ) -> WebExtensionCleanupErrorClassification {
        WebExtensionStorageCleanupOwner(manager: self)
            .classifyCleanupErrors(
                errors,
                for: extensionId,
                preCleanupSnapshot: preCleanupSnapshot,
                postCleanupSnapshot: postCleanupSnapshot
            )
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

    func makeWebExtensionCleanupErrorDiagnostic(
        _ error: Error
    ) -> WebExtensionCleanupErrorDiagnostic {
        WebExtensionStorageCleanupOwner(manager: self)
            .makeCleanupErrorDiagnostic(error)
    }

    func isBenignMissingOptionalWebExtensionStoreError(
        _ diagnostic: WebExtensionCleanupErrorDiagnostic,
        extensionId: String,
        preCleanupSnapshot: WebExtensionStorageSnapshot,
        postCleanupSnapshot: WebExtensionStorageSnapshot,
        hasNonOptionalFailureSignals: Bool
    ) -> Bool {
        WebExtensionStorageCleanupOwner(manager: self)
            .isBenignMissingOptionalStoreError(
                diagnostic,
                extensionId: extensionId,
                preCleanupSnapshot: preCleanupSnapshot,
                postCleanupSnapshot: postCleanupSnapshot,
                hasNonOptionalFailureSignals: hasNonOptionalFailureSignals
            )
    }
}
