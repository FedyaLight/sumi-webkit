import Foundation

/// Demand-scoped native-messaging resources. Construction is passive; the
/// wake scheduler and relay are materialized only by a native-messaging
/// operation, while teardown can inspect resident resources without creating
/// them.
@available(macOS 15.5, *)
@MainActor
final class ExtensionDemandScopedNativeMessagingOwners {
    private let moduleRegistry: SumiModuleRegistry
    private let importStore: SafariExtensionImportStore
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private var wakeOwnerStorage: ExtensionNativeMessagingBackgroundWakeOwner?
    private var relayOwnerStorage: ExtensionNativeMessagingRelayOwner?

    init(
        moduleRegistry: SumiModuleRegistry,
        importStore: SafariExtensionImportStore,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    ) {
        self.moduleRegistry = moduleRegistry
        self.importStore = importStore
        self.runtimeLifecycle = runtimeLifecycle
    }

    func wakeOwner() -> ExtensionNativeMessagingBackgroundWakeOwner {
        if let wakeOwnerStorage { return wakeOwnerStorage }
        let owner = ExtensionNativeMessagingBackgroundWakeOwner()
        wakeOwnerStorage = owner
        return owner
    }

    func relayOwner() -> ExtensionNativeMessagingRelayOwner {
        if let relayOwnerStorage { return relayOwnerStorage }
        let owner = ExtensionNativeMessagingRelayOwner(
            moduleRegistry: moduleRegistry,
            importStore: importStore,
            runtimeLifecycle: runtimeLifecycle
        )
        relayOwnerStorage = owner
        return owner
    }

    func withLoadedWakeOwner(
        _ operation: (ExtensionNativeMessagingBackgroundWakeOwner) -> Void
    ) {
        guard let wakeOwnerStorage else { return }
        operation(wakeOwnerStorage)
    }

    func withLoadedRelayOwner(
        _ operation: (ExtensionNativeMessagingRelayOwner) -> Void
    ) {
        guard let relayOwnerStorage else { return }
        operation(relayOwnerStorage)
    }

    #if DEBUG
        func loadedWakeTasksForDrain() -> [Task<Void, Never>] {
            wakeOwnerStorage?.runtimeTasksForDrain() ?? []
        }
    #endif
}
