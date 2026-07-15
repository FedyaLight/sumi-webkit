import Foundation

/// Terminal native-messaging session operations. Callers cannot retrieve the
/// port registry, relay owner, or demand authority independently.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingSessionControl {
    private let ports: ExtensionNativeMessagingPortRegistry
    private let owners: ExtensionDemandScopedNativeMessagingOwners
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        ports: ExtensionNativeMessagingPortRegistry,
        owners: ExtensionDemandScopedNativeMessagingOwners,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.ports = ports
        self.owners = owners
        self.diagnostics = diagnostics
    }

    func cancelAll(reason: String) {
        diagnostics.trace(
            "nativeMessagingCancelSessions reason=\(reason) count=\(ports.count)"
        )
        ports.disconnectAll()
        owners.withLoadedRelayOwner {
            $0.loadedRelay?.clearAllLoopGuardState()
        }
    }

    func diagnosticsAdapterRegistry() -> SumiNativeMessagingAdapterRegistry {
        var registry: SumiNativeMessagingAdapterRegistry?
        owners.withLoadedRelayOwner {
            registry = $0.loadedRelay?.diagnosticsAdapterRegistry
        }
        return registry ?? .production()
    }

    #if DEBUG
        func runtimeTasksForDrain() -> [Task<Void, Never>] {
            owners.loadedWakeTasksForDrain()
        }
    #endif
}
