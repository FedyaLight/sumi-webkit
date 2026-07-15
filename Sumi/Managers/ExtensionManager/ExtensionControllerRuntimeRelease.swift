import Foundation

/// Releases terminal WebKit controller/data-store ownership after all context
/// bindings and runtime bookkeeping have been retired.
@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerRuntimeRelease {
    private let browserConfiguration: BrowserConfiguration
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private let runtimeDemand: ExtensionRuntimeDemandAuthority
    private let controllerDelegateReadiness:
        ExtensionControllerDelegateReadiness

    init(
        browserConfiguration: BrowserConfiguration,
        profileRuntime: ExtensionProfileRuntime,
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority,
        runtimeDemand: ExtensionRuntimeDemandAuthority,
        controllerDelegateReadiness:
            ExtensionControllerDelegateReadiness
    ) {
        self.browserConfiguration = browserConfiguration
        self.profileRuntime = profileRuntime
        self.runtimeLifecycle = runtimeLifecycle
        self.runtimeDemand = runtimeDemand
        self.controllerDelegateReadiness = controllerDelegateReadiness
    }

    func releaseAfterShutdown() {
        controllerDelegateReadiness.cancelAll()
        browserConfiguration.webViewConfiguration.webExtensionController = nil
        for controller in profileRuntime.controllersByProfile.values {
            controller.delegate = nil
        }
        profileRuntime.replaceControllers([:])
        profileRuntime.removeAllWebsiteDataStores()
        runtimeDemand.reset()
        runtimeLifecycle.resetAfterShutdown()
    }
}
