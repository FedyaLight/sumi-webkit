import Foundation

/// Loads the persisted extension catalog and publishes one coherent snapshot.
/// It does not install packages or start WebKit runtimes.
@available(macOS 15.5, *)
@MainActor
final class InstalledExtensionCatalog {
    struct Environment {
        let metadataStore: ExtensionInstallationMetadataStore
        let installedRecords: InstalledExtensionCollection
        let liveContextCount: @MainActor () -> Int
        let markCatalogLoaded: @MainActor () -> Void
        let trace: @MainActor (String) -> Void
    }

    private let environment: Environment

    init(environment: Environment) {
        self.environment = environment
    }

    @discardableResult
    func load() -> [ExtensionEntity] {
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
            "loadInstalledExtensionMetadata start installedContexts=\(environment.liveContextCount())"
        )
        let result = environment.metadataStore.loadInstalledExtensionMetadata {
            trace($0)
        }
        return publish(result)
    }

    @discardableResult
    func publish(
        _ result: ExtensionInstallationMetadataStore.MetadataLoadResult
    ) -> [ExtensionEntity] {
        environment.installedRecords.setAll(result.records)
        environment.markCatalogLoaded()
        trace(
            "loadInstalledExtensionMetadata complete records=\(result.records.count) enabled=\(result.enabledEntities.count)"
        )
        return result.enabledEntities
    }

    private func trace(_ message: @autoclosure () -> String) {
        guard ExtensionManager.isWebKitRuntimeTraceEnabled else { return }
        environment.trace(message())
    }
}

@available(macOS 15.5, *)
extension InstalledExtensionCatalog.Environment {
    @MainActor
    static func makeLive(manager: ExtensionManager) -> Self {
        Self(
            metadataStore: manager.installationMetadataStore,
            installedRecords: manager.installedExtensionCollection,
            liveContextCount: { [weak manager] in
                manager?.profileRuntime.contextsForCurrentProfile().count ?? 0
            },
            markCatalogLoaded: { [weak manager] in
                manager?.extensionsLoaded = true
            },
            trace: { [weak manager] message in
                manager?.runtimeDiagnostics.trace(message)
            }
        )
    }
}
