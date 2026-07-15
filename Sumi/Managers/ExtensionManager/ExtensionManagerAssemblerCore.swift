import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionManagerCoreAssembly {
    let actionPolicy: ExtensionActionPolicyAssemblyProduct
    let popup: ExtensionPopupAssemblyProduct
    let contextLoading: ExtensionContextLoadingAssemblyProduct
    let contextLifecycle: ExtensionContextLifecycleCoreProduct
    let controller: ExtensionControllerCoreAssemblyProduct
    let nativeMessaging: ExtensionNativeMessagingAssemblyProduct
    let retirement: ExtensionRuntimeRetirementAssemblyProduct
    #if DEBUG
        var inspectionDidAssemble:
            ExtensionManagerTestInspection.DidAssemble?
    #endif
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionManagerAssembler {
    static func assemble(
        _ foundation: ExtensionManagerAssemblyFoundation
    ) -> ExtensionManagerAssemblyResult {
        let core = assembleCore(foundation)
        return assembleRuntime(
            foundation,
            core: core
        )
    }

    #if DEBUG
        static func assemble(
            _ foundation: ExtensionManagerAssemblyFoundation,
            testInspectionDidAssemble:
                ExtensionManagerTestInspection.DidAssemble?,
            testAssemblyOverrides:
                ExtensionManagerTestAssemblyOverrides?
        ) -> ExtensionManagerAssemblyResult {
            var core = assembleCore(foundation)
            core.contextLifecycle.retirement.installDebugOperations(
                unloadContext: testAssemblyOverrides?.unloadContext,
                isLoadedContext: testAssemblyOverrides?.isLoadedContext
            )
            core.actionPolicy.actionSurfaces.installDebugFinalization(
                backgroundWake:
                    testAssemblyOverrides?.actionFinalization?.backgroundWake,
                reconcileOpenTabs:
                    testAssemblyOverrides?.actionFinalization?.reconcile
            )
            core.inspectionDidAssemble = testInspectionDidAssemble
            return assembleRuntime(foundation, core: core)
        }
    #endif

    private static func assembleCore(
        _ f: ExtensionManagerAssemblyFoundation
    ) -> ExtensionManagerCoreAssembly {
        let callbackAdmission = ExtensionControllerCallbackAdmission(
            profileRuntime: f.runtime.profileRuntime,
            extensionLoadRevisions: f.runtime.loadRevisions
        )
        let popup = assemblePopup(f)
        let contextState = assembleContextState(
            f,
            popupRetirement: popup.runtimeRetirement
        )
        let nativeMessaging = assembleNativeMessaging(
            f,
            callbackAdmission: callbackAdmission
        )
        let actionPolicy = assembleActionPolicy(
            f,
            contextAuthority: contextState.loading.authority,
            backgroundWakes: nativeMessaging.backgroundWakes
        )
        return finishCoreAssembly(
            f,
            callbackAdmission: callbackAdmission,
            popup: popup,
            contextLoading: contextState.loading,
            contextLifecycle: contextState.lifecycle,
            nativeMessaging: nativeMessaging,
            actionPolicy: actionPolicy
        )
    }

    private static func finishCoreAssembly(
        _ f: ExtensionManagerAssemblyFoundation,
        callbackAdmission: ExtensionControllerCallbackAdmission,
        popup: ExtensionPopupAssemblyProduct,
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        nativeMessaging: ExtensionNativeMessagingAssemblyProduct,
        actionPolicy: ExtensionActionPolicyAssemblyProduct
    ) -> ExtensionManagerCoreAssembly {
        let controller = assembleControllerCore(
            f,
            callbackAdmission: callbackAdmission,
            actionPolicy: actionPolicy,
            nativeMessaging: nativeMessaging
        )
        let retirement = assembleRetirement(
            f,
            contextLoading: contextLoading,
            contextLifecycle: contextLifecycle,
            actionPolicy: actionPolicy,
            nativeMessaging: nativeMessaging
        )
        return ExtensionManagerCoreAssembly(
            actionPolicy: actionPolicy,
            popup: popup,
            contextLoading: contextLoading,
            contextLifecycle: contextLifecycle,
            controller: controller,
            nativeMessaging: nativeMessaging,
            retirement: retirement
        )
    }
}
