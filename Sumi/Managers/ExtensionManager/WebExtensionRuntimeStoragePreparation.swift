import Foundation
import WebKit

/// Prepares the exact WebKit storage scope used by one controller/context
/// load. It never re-resolves a current profile or installed record.
@available(macOS 15.5, *)
@MainActor
struct WebExtensionRuntimeStoragePreparation {
    private let extensionID: String
    private let runtimeIdentifier: String
    private let storage: WebExtensionStorageCleanupStore

    init(
        extensionID: String,
        runtimeIdentifier: String,
        controller: WKWebExtensionController,
        planner: WebExtensionStorageCleanupPlanner,
        libraryDirectoryProvider: @escaping () -> URL? = {
            FileManager.default.urls(
                for: .libraryDirectory,
                in: .userDomainMask
            ).first
        },
        fileManager: FileManager = .default
    ) {
        self.extensionID = extensionID
        self.runtimeIdentifier = runtimeIdentifier
        self.storage = WebExtensionStorageCleanupStore(
            controllerStorageId: controller.configuration.identifier,
            libraryDirectoryProvider: libraryDirectoryProvider,
            fileManager: fileManager,
            planner: planner,
            storageDirectoryNameResolver: { _ in runtimeIdentifier }
        )
    }

    func prepare() {
        storage.adoptLegacyStorageDirectoryIfNeeded(
            for: extensionID,
            resolvedStorageName: runtimeIdentifier
        )
        _ = storage.ensureDirectoryExists(for: extensionID)
    }

    func snapshot() -> WebExtensionStorageCleanupPlanner.StorageSnapshot {
        storage.snapshot(for: extensionID)
    }

    func traceLifecycle(
        phase: String,
        capabilitySnapshot: @autoclosure () ->
            WebExtensionStorageCleanupPlanner.StoreCapabilitySnapshot,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        guard RuntimeDiagnostics.isVerboseEnabled else { return }
        let storageSnapshot = snapshot()
        let capabilitySnapshot = capabilitySnapshot()
        diagnostics.trace(
            "storeLifecycle phase=\(phase) extensionId=\(extensionID) runtimeIdentifier=\(runtimeIdentifier) directoryExists=\(storageSnapshot.directoryExists) entries=\(storageSnapshot.entryNames.joined(separator: ",")) registeredContentScripts=\(storageSnapshot.hasRegisteredContentScriptsStore) localStorage=\(storageSnapshot.hasLocalStorageStore) syncStorage=\(storageSnapshot.hasSyncStorageStore) onlyPrunable=\(storageSnapshot.hasOnlyPrunableEntries) webKitCompat=\(capabilitySnapshot.usesWebKitCompatibilityPrelude) mayTouchDynamicContentScripts=\(capabilitySnapshot.mayTouchDynamicContentScriptStore) mayTouchSyncStorage=\(capabilitySnapshot.mayTouchSyncStorageStore) permissions=\(capabilitySnapshot.declaredPermissions.joined(separator: ",")) unsupportedAPIs=\(capabilitySnapshot.unsupportedAPIs.joined(separator: ","))"
        )
    }
}
