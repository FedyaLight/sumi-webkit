import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingRelayOwner {
    private let moduleRegistry: SumiModuleRegistry
    private let importStore: SafariExtensionImportStore
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private var relayStorage: SumiNativeMessagingRelay?

    init(
        moduleRegistry: SumiModuleRegistry,
        importStore: SafariExtensionImportStore,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    ) {
        self.moduleRegistry = moduleRegistry
        self.importStore = importStore
        self.runtimeLifecycle = runtimeLifecycle
    }

    var extensionsModuleEnabledForCallbacks: Bool {
        moduleRegistry.isEnabledForRuntimeBoundary(.extensions)
    }

    var relay: SumiNativeMessagingRelay {
        if let relayStorage {
            return relayStorage
        }

        let relay = SumiNativeMessagingRelay.production(
            importStore: importStore,
            extensionsModuleEnabled: { [weak self] in
                self?.extensionsModuleEnabledForCallbacks ?? false
            },
            profileRuntimeLoaded: { [runtimeLifecycle] in
                runtimeLifecycle.isReadyOrLoading
            }
        )
        relayStorage = relay
        return relay
    }

    var loadedRelay: SumiNativeMessagingRelay? {
        relayStorage
    }

    #if DEBUG
        /// Installs a relay with test-controlled launcher/adapters so hosted
        /// tests can model the external companion-application boundary
        /// without launching a real application.
        func installRelayForTesting(_ relay: SumiNativeMessagingRelay) {
            relayStorage = relay
        }
    #endif
}
