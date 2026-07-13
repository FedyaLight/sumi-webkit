import Foundation

@available(macOS 15.5, *)
@MainActor
extension ExtensionInstallationService {
    static func makeLive(manager: ExtensionManager) -> Self {
        let recordTransaction = ExtensionInstallationRecordTransaction(
            persistence: manager.installationMetadataStore,
            installedRecords: manager.installedExtensionCollection
        )
        let runtimeReplacement = ExtensionInstallationRuntimeReplacement(
            retirement: manager.runtimeRetirement,
            recovery: manager.runtimeRecovery
        )
        return Self(
            metadataStore: manager.installationMetadataStore,
            recordTransaction: recordTransaction,
            runtimeActivation: manager.installationRuntimeActivation,
            runtimeReplacement: runtimeReplacement,
            failureSettlement: ExtensionInstallationFailureSettlement(
                recordTransaction: recordTransaction,
                runtimeReplacement: runtimeReplacement
            ),
            mutationRegistry: manager.runtimeMutationRegistry,
            loadRegistry: manager.contextLoadRegistry,
            sourceAdmission: ExtensionInstallationAdmission(),
            activePackageGenerations: manager.activePackageGenerations,
            packageMaintenance: ExtensionPackageMaintenance(
                layout: ExtensionPackageLayout(
                    extensionsRoot: ExtensionUtils.extensionsDirectory()
                ),
                activeGenerations: manager.activePackageGenerations
            ),
            packageFileExecutor: ExtensionPackageFileExecutor(),
            requestRuntimeForInstallation: { [weak manager] in
                _ = await manager?.runtimeLifecycleOwner
                    .requestExtensionRuntimeAndWait(
                        reason: .install,
                        allowWithoutEnabledExtensions: true
                    )
            },
            removeStoredData: { [weak manager] extensionID, mode in
                await manager?.removeStoredWebExtensionData(
                    for: extensionID,
                    mode: mode
                )
            },
            hasStoredDataCandidate: { [weak manager] extensionID in
                manager?.hasStoredWebExtensionDataCandidate(for: extensionID)
                    ?? false
            },
            traceStoreLifecycle: {
                [weak manager] phase, extensionID, manifest in
                manager?.traceWebExtensionStoreLifecycle(
                    phase: phase,
                    extensionId: extensionID,
                    manifest: manifest
                )
            },
            ensureStorageDirectory: { [weak manager] extensionID in
                _ = manager?.ensureWebExtensionStorageDirectoryExists(
                    for: extensionID
                )
            },
            debugBeforePersist: { [weak manager] in
                #if DEBUG
                    manager?.testHooks.beforePersistInstalledRecord
                #else
                    nil
                #endif
            },
            emitTrace: { [weak manager] message in
                guard ExtensionManager.isWebKitRuntimeTraceEnabled else {
                    return
                }
                manager?.runtimeDiagnostics.trace(message)
            }
        )
    }
}
