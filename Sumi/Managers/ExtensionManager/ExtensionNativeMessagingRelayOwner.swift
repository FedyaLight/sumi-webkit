import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingRelayOwner {
    private weak var manager: ExtensionManager?
    private var relayStorage: SumiNativeMessagingRelay?

    init(manager: ExtensionManager) {
        self.manager = manager
    }

    var extensionsModuleEnabledForCallbacks: Bool {
        guard let manager else { return false }
        switch manager.runtime.extensionsModuleEnabled() {
        case .enabled(let isEnabled):
            return isEnabled
        case .unavailable:
            return manager.moduleRegistry.isEnabled(.extensions)
        }
    }

    var relay: SumiNativeMessagingRelay {
        if let relayStorage {
            return relayStorage
        }

        let relay = SumiNativeMessagingRelay.production(
            extensionsModuleEnabled: { [weak self] in
                self?.extensionsModuleEnabledForCallbacks ?? false
            },
            profileRuntimeLoaded: { [weak self] in
                guard let manager = self?.manager else { return false }
                return manager.runtimeState == .ready || manager.runtimeState == .loading
            }
        )
        relayStorage = relay
        return relay
    }

    var loadedRelay: SumiNativeMessagingRelay? {
        relayStorage
    }
}
