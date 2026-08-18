import Foundation

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleContextControllerTransactionPhase(
        runtime: ExtensionRuntimeAuthorityFoundation,
        actions: ExtensionActionGraphFoundation,
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        controller: ExtensionControllerCoreAssemblyProduct,
        retirement: ExtensionRuntimeRetirementAssemblyProduct
    ) -> ExtensionContextControllerTransaction {
        let transaction = ExtensionContextControllerTransaction(
            authority: contextLoading.authority,
            profileRuntime: runtime.profileRuntime,
            rollback: retirement.rollback,
            errorObservation: contextLifecycle.errors,
            runtimeMetrics: runtime.metrics,
            diagnostics: runtime.diagnostics,
            expectedControllerDelegate: controller.delegateBridge,
            controllerDelegateReadiness: controller.delegateReadiness
        )
        #if DEBUG
            transaction.installDebugBeforeControllerLoad {
                [debug = actions.debugSignals] in
                debug.beforeControllerLoad
            }
        #endif
        return transaction
    }

    static func assembleContextLoaderPhase(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        browser: ExtensionManagerBrowserFoundation,
        actionPolicy: ExtensionActionPolicyAssemblyProduct,
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        controller: ExtensionControllerCoreAssemblyProduct,
        transaction: ExtensionContextControllerTransaction,
        bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission
    ) -> ExtensionContextLoader {
        ExtensionContextLoader(
            authority: contextLoading.authority,
            profileRuntime: runtime.profileRuntime,
            controllerProvisioning: controller.provisioning,
            waitForWebsiteDataMutationAdmission: {
                [websiteData = browser.websiteData] profileID in
                await websiteData.wait(profileID: profileID)
            },
            sourceCache: contextLoading.sourceCache,
            contextPreparation: actionPolicy.contextPreparation,
            runtimeMetrics: runtime.metrics,
            diagnostics: runtime.diagnostics,
            expectedControllerDelegate: controller.delegateBridge,
            controllerTransaction: transaction,
            bootstrapChromeAdmission: bootstrapChromeAdmission
        )
    }
}
