import Foundation

/// Releases terminal WebKit controller/data-store ownership after all context
/// bindings and runtime bookkeeping have been retired.
@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerRuntimeRelease {
    private let runtimeLifecycle: ExtensionRuntimeLifecycleAuthority
    private let runtimeDemand: ExtensionRuntimeDemandAuthority
    private let controllerDelegateReadiness:
        ExtensionControllerDelegateReadiness
    private let controllerProvisioning: ExtensionControllerProvisioningOwner

    init(
        runtimeLifecycle: ExtensionRuntimeLifecycleAuthority,
        runtimeDemand: ExtensionRuntimeDemandAuthority,
        controllerDelegateReadiness:
            ExtensionControllerDelegateReadiness,
        controllerProvisioning: ExtensionControllerProvisioningOwner
    ) {
        self.runtimeLifecycle = runtimeLifecycle
        self.runtimeDemand = runtimeDemand
        self.controllerDelegateReadiness = controllerDelegateReadiness
        self.controllerProvisioning = controllerProvisioning
    }

    func releaseAfterShutdown() {
        controllerDelegateReadiness.cancelAll()
        controllerProvisioning.releaseUserRuntime()
        runtimeDemand.reset()
        runtimeLifecycle.resetAfterShutdown()
    }
}
