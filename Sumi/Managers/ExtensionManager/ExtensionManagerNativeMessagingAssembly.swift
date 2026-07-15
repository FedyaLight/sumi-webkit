import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionNativeMessagingAssemblyProduct {
    let owners: ExtensionDemandScopedNativeMessagingOwners
    let backgroundWakes: ExtensionBackgroundWakeCoordinator
    let messageSettlement: ExtensionNativeMessageSendSettlement
    let portSettlement: ExtensionNativePortConnectionSettlement
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleNativeMessaging(
        _ f: ExtensionManagerAssemblyFoundation,
        callbackAdmission: ExtensionControllerCallbackAdmission
    ) -> ExtensionNativeMessagingAssemblyProduct {
        let owners = ExtensionDemandScopedNativeMessagingOwners(
            moduleRegistry: f.contexts.moduleRegistry,
            runtimeLifecycle: f.runtime.lifecycle
        )
        let backgroundWakes = makeBackgroundWakes(
            f,
            nativeMessagingOwners: owners
        )
        return ExtensionNativeMessagingAssemblyProduct(
            owners: owners,
            backgroundWakes: backgroundWakes,
            messageSettlement: ExtensionNativeMessageSendSettlement(
                admission: callbackAdmission,
                relayOwner: { [owners] in owners.relayOwner() },
                backgroundWakes: backgroundWakes,
                profileRuntime: f.runtime.profileRuntime,
                installedExtensions: f.contexts.installedExtensions,
                diagnostics: f.runtime.diagnostics
            ),
            portSettlement: ExtensionNativePortConnectionSettlement(
                admission: callbackAdmission,
                registry: f.controller.nativeMessagingPorts,
                relayOwner: { [owners] in owners.relayOwner() },
                backgroundWakes: backgroundWakes,
                profileRuntime: f.runtime.profileRuntime,
                installedExtensions: f.contexts.installedExtensions,
                diagnostics: f.runtime.diagnostics
            )
        )
    }
}
