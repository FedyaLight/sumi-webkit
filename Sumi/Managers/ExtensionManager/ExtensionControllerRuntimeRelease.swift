import Foundation

/// Releases terminal WebKit controller/data-store ownership after all context
/// bindings and runtime bookkeeping have been retired.
@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerRuntimeRelease {
    private let browserConfiguration: BrowserConfiguration
    private let profileRuntime: ExtensionProfileRuntime
    private let runtimeSession: ExtensionRuntimeSession

    init(
        browserConfiguration: BrowserConfiguration,
        profileRuntime: ExtensionProfileRuntime,
        runtimeSession: ExtensionRuntimeSession
    ) {
        self.browserConfiguration = browserConfiguration
        self.profileRuntime = profileRuntime
        self.runtimeSession = runtimeSession
    }

    func release(isExtensionSupportAvailable: Bool) {
        browserConfiguration.webViewConfiguration.webExtensionController = nil
        for controller in profileRuntime.controllersByProfile.values {
            controller.delegate = nil
        }
        profileRuntime.replaceControllers([:])
        profileRuntime.removeAllWebsiteDataStores()
        runtimeSession.allowsRuntimeWithoutEnabledExtensions = false
        runtimeSession.runtimeState =
            isExtensionSupportAvailable ? .idle : .unavailable
    }
}
