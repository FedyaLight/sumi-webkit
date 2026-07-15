import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionContextRuntimeLifetime {
    private let moduleRegistry: SumiModuleRegistry
    private let profileRuntime: ExtensionProfileRuntime
    private let lifecycle: ExtensionRuntimeLifecycleAuthority
    private let demand: ExtensionRuntimeDemandAuthority
    private let loadStatus: ExtensionRuntimeLoadStatusAuthority
    private let catalog: ExtensionRuntimeCatalog
    private let residency: ExtensionRuntimeResidencyAuthority
    private let metrics: ExtensionRuntimeMetricsAuthority

    init(
        moduleRegistry: SumiModuleRegistry,
        profileRuntime: ExtensionProfileRuntime,
        lifecycle: ExtensionRuntimeLifecycleAuthority,
        demand: ExtensionRuntimeDemandAuthority,
        loadStatus: ExtensionRuntimeLoadStatusAuthority,
        catalog: ExtensionRuntimeCatalog,
        residency: ExtensionRuntimeResidencyAuthority,
        metrics: ExtensionRuntimeMetricsAuthority
    ) {
        self.moduleRegistry = moduleRegistry
        self.profileRuntime = profileRuntime
        self.lifecycle = lifecycle
        self.demand = demand
        self.loadStatus = loadStatus
        self.catalog = catalog
        self.residency = residency
        self.metrics = metrics
    }
}
