//
//  WebExtensionStorageCleanupOwner.swift
//  Sumi
//
//  Coordinates WebKit record deletion, storage snapshots, and diagnostics for
//  WebExtension cleanup. Install and runtime loading flows stay with
//  ExtensionManager+Installation.
//

import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class WebExtensionStorageCleanupOwner {
    private let profileRuntime: ExtensionProfileRuntime
    private let installedExtensions: InstalledExtensionCollection
    private let diagnostics: ExtensionRuntimeDiagnostics
    private let resolvedProfileID: @MainActor (UUID?) -> UUID?
    private let controllerStorageID: @MainActor (UUID) -> UUID
    private let persistentProfileIDs: @MainActor () throws -> [UUID]
    private let controllerForProfile:
        @MainActor (UUID) -> WKWebExtensionController?
    #if DEBUG
        private var debugDataCleanup: (@MainActor ()
            -> (@MainActor (String) async -> Bool)?)?
    #endif

    init(
        profileRuntime: ExtensionProfileRuntime,
        installedExtensions: InstalledExtensionCollection,
        diagnostics: ExtensionRuntimeDiagnostics,
        resolvedProfileID: @escaping @MainActor (UUID?) -> UUID?,
        controllerStorageID: @escaping @MainActor (UUID) -> UUID,
        persistentProfileIDs: @escaping @MainActor () throws -> [UUID],
        controllerForProfile:
            @escaping @MainActor (UUID) -> WKWebExtensionController?
    ) {
        self.profileRuntime = profileRuntime
        self.installedExtensions = installedExtensions
        self.diagnostics = diagnostics
        self.resolvedProfileID = resolvedProfileID
        self.controllerStorageID = controllerStorageID
        self.persistentProfileIDs = persistentProfileIDs
        self.controllerForProfile = controllerForProfile
    }

    #if DEBUG
        func installDebugDataCleanup(
            _ provider: @escaping @MainActor ()
                -> (@MainActor (String) async -> Bool)?
        ) {
            debugDataCleanup = provider
        }
    #endif

    func removeStoredData(for extensionId: String) async {
        traceLifecycle(
            phase: "cleanup-start",
            extensionId: extensionId
        )
        let hasDataCandidate = hasStoredDataCandidate(for: extensionId)
        if hasDataCandidate == false {
            finalizeCleanup(for: extensionId)
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
                finalizeCleanup(for: extensionId)
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

        guard matchingRecords.isEmpty == false else {
            finalizeCleanup(for: extensionId)
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
        finalizeCleanup(for: extensionId)
        if RuntimeDiagnostics.isVerboseEnabled {
            if errors.isEmpty {
                diagnostics.trace(
                    "Removed stored WebExtension data for \(extensionId)"
                )
            } else {
                diagnostics.trace(
                    "Removed stored WebExtension data for \(extensionId) with record errors: \(errors.map(\.localizedDescription).joined(separator: " | "))"
                )
            }
        }
        traceLifecycle(
            phase: "cleanup-finished",
            extensionId: extensionId
        )
    }

    func removeAllStoredData(for extensionId: String) async throws {
        traceLifecycle(phase: "cleanup-all-start", extensionId: extensionId)

        var profileIDs = Set(try persistentProfileIDs())
        profileIDs.formUnion(profileRuntime.controllersByProfile.keys)
        if let currentProfileID = resolvedProfileID(nil) {
            profileIDs.insert(currentProfileID)
        }

        var controllers = profileRuntime.controllersByProfile
        for profileID in profileIDs where controllers[profileID] == nil {
            guard let controller = controllerForProfile(profileID) else {
                throw ExtensionError.installationFailed(
                    "Could not open extension storage for profile \(profileID.uuidString)"
                )
            }
            controllers[profileID] = controller
        }

        let dataCleanupOwner = WebExtensionControllerDataCleanupOwner()
        let matchingRecords = await dataCleanupOwner.matchingRecords(
            for: extensionId,
            controllersByProfile: controllers,
            additionalUniqueIdentifiers: safariRuntimeIdentifiers(
                for: extensionId
            )
        )
        if matchingRecords.isEmpty == false {
            await dataCleanupOwner.remove(
                matchingRecords,
                extensionId: extensionId,
                using: controllers
            )
        }

        for profileID in profileIDs {
            try storageCleanupStore(profileId: profileID)
                .deleteStorageDirectory(for: extensionId)
        }

        traceLifecycle(phase: "cleanup-all-finished", extensionId: extensionId)
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

    private func finalizeCleanup(for extensionId: String) {
        _ = pruneEmptyOrStateOnlyStorageDirectory(for: extensionId)
    }

    private func storageCleanupStore(
        profileId: UUID? = nil
    ) -> WebExtensionStorageCleanupStore {
        let resolvedProfileId = resolvedProfileID(profileId)
        return WebExtensionStorageCleanupStore(
            controllerStorageId: resolvedProfileId.map(controllerStorageID),
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

    func storageSnapshot(
        for extensionId: String
    ) -> WebExtensionStorageCleanupStore.StorageSnapshot {
        storageCleanupStore().snapshot(for: extensionId)
    }

    func traceLifecycle(
        phase: String,
        extensionId: String
    ) {
        guard ExtensionManager.isWebKitRuntimeTraceEnabled else { return }
        let snapshot = storageSnapshot(for: extensionId)
        let message =
            "storeLifecycle phase=\(phase) extensionId=\(extensionId) directoryExists=\(snapshot.directoryExists) entries=\(snapshot.entryNames.joined(separator: ",")) onlyPrunable=\(snapshot.hasOnlyPrunableEntries)"

        diagnostics.trace(message)
    }
}
