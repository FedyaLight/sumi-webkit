import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionNativeMessagingRelayOwner {
    struct Dependencies {
        let extensionsModuleEnabled: @MainActor () -> ExtensionManagerRuntime.ModuleEnabledState
        let moduleRegistryExtensionsEnabled: @MainActor () -> Bool
        let profileRuntimeLoaded: @MainActor () -> Bool
    }

    private let dependencies: Dependencies
    private var relayStorage: SumiNativeMessagingRelay?

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    var extensionsModuleEnabledForCallbacks: Bool {
        switch dependencies.extensionsModuleEnabled() {
        case .enabled(let isEnabled):
            return isEnabled
        case .unavailable:
            return dependencies.moduleRegistryExtensionsEnabled()
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
                self?.dependencies.profileRuntimeLoaded() ?? false
            }
        )
        relayStorage = relay
        return relay
    }

    var loadedRelay: SumiNativeMessagingRelay? {
        relayStorage
    }
}

@available(macOS 15.5, *)
extension ExtensionNativeMessagingRelayOwner.Dependencies {
    static func live(manager: ExtensionManager) -> Self {
        Self(
            extensionsModuleEnabled: { [weak manager] in
                manager?.runtime.extensionsModuleEnabled() ?? .unavailable
            },
            moduleRegistryExtensionsEnabled: { [weak manager] in
                manager?.moduleRegistry.isEnabled(.extensions) ?? false
            },
            profileRuntimeLoaded: { [weak manager] in
                guard let manager else { return false }
                return manager.runtimeState == .ready || manager.runtimeState == .loading
            }
        )
    }
}
