import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionControllerLifetimeOwner {
    private let browserConfiguration: BrowserConfiguration
    private let provisioning: ExtensionControllerProvisioningOwner
    private let delegateBridge: ExtensionControllerDelegateBridge
    private let callbackAdmission: ExtensionControllerCallbackAdmission
    private let browserCallbacks:
        ExtensionBrowserAttachmentAuthority.ControllerCallbacks
    private let permissionPreludes:
        ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner
    private let nativeMessagingSessions: ExtensionNativeMessagingSessionControl

    init(
        browserConfiguration: BrowserConfiguration,
        provisioning: ExtensionControllerProvisioningOwner,
        delegateBridge: ExtensionControllerDelegateBridge,
        callbackAdmission: ExtensionControllerCallbackAdmission,
        browserCallbacks:
            ExtensionBrowserAttachmentAuthority.ControllerCallbacks,
        permissionPreludes:
            ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner,
        nativeMessagingSessions: ExtensionNativeMessagingSessionControl
    ) {
        self.browserConfiguration = browserConfiguration
        self.provisioning = provisioning
        self.delegateBridge = delegateBridge
        self.callbackAdmission = callbackAdmission
        self.browserCallbacks = browserCallbacks
        self.permissionPreludes = permissionPreludes
        self.nativeMessagingSessions = nativeMessagingSessions
    }
}
