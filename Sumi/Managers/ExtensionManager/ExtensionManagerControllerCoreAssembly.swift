import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionControllerCoreAssemblyProduct {
    let callbackAdmission: ExtensionControllerCallbackAdmission
    let permissionSettlement: ExtensionPermissionCallbackSettlement
    let urlPermissionSettlement: ExtensionURLPermissionCallbackSettlement
    let delegateBridge: ExtensionControllerDelegateBridge
    let delegateReadiness: ExtensionControllerDelegateReadiness
    let provisioning: ExtensionControllerProvisioningOwner
    let runtimeAccess: ExtensionRuntimeAccess
    let permissionPreludes: ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleControllerCore(
        _ f: ExtensionManagerAssemblyFoundation,
        callbackAdmission: ExtensionControllerCallbackAdmission,
        actionPolicy: ExtensionActionPolicyAssemblyProduct,
        nativeMessaging: ExtensionNativeMessagingAssemblyProduct
    ) -> ExtensionControllerCoreAssemblyProduct {
        let permissionSettlement = ExtensionPermissionCallbackSettlement(
            admission: callbackAdmission,
            decisions: actionPolicy.permissionDecisions,
            siteAccess: actionPolicy.siteAccess,
            prompt: actionPolicy.permissionPrompt
        )
        let urlPermissionSettlement = ExtensionURLPermissionCallbackSettlement(
            admission: callbackAdmission,
            decisions: actionPolicy.permissionDecisions,
            siteAccess: actionPolicy.siteAccess,
            prompt: actionPolicy.permissionPrompt
        )
        let delegateBridge = ExtensionControllerDelegateBridge(
            callbackAdmission: callbackAdmission,
            permissions: permissionSettlement,
            urlPermissions: urlPermissionSettlement,
            nativeMessages: nativeMessaging.messageSettlement,
            nativePorts: nativeMessaging.portSettlement
        )
        let delegateReadiness = ExtensionControllerDelegateReadiness(
            profileRuntime: f.runtime.profileRuntime,
            bind: { [delegateBridge, diagnostics = f.runtime.diagnostics] receipt in
                receipt.controller.delegate = delegateBridge
                diagnostics.traceNativeMessagingContextBinding(
                    phase: "delegateRebound",
                    extensionId: nil,
                    profileId: receipt.profileID,
                    controller: receipt.controller,
                    profileController: receipt.controller,
                    expectedControllerDelegate: delegateBridge
                )
            }
        )
        let provisioning = makeControllerProvisioning(
            f,
            delegateBridge: delegateBridge,
            delegateReadiness: delegateReadiness
        )
        return ExtensionControllerCoreAssemblyProduct(
            callbackAdmission: callbackAdmission,
            permissionSettlement: permissionSettlement,
            urlPermissionSettlement: urlPermissionSettlement,
            delegateBridge: delegateBridge,
            delegateReadiness: delegateReadiness,
            provisioning: provisioning,
            runtimeAccess: ExtensionRuntimeAccess(
                profileRuntime: f.runtime.profileRuntime,
                controllerProvisioningOwner: provisioning
            ),
            permissionPreludes: makePermissionPreludes(f)
        )
    }
}
