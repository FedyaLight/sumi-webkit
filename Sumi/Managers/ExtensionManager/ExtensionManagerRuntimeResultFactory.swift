import Foundation

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func makeRuntimeControllerResult(
        controller: ExtensionControllerGraphFoundation,
        browser: ExtensionManagerBrowserFoundation,
        controllerCore: ExtensionControllerCoreAssemblyProduct,
        services: ExtensionRuntimeServicePhaseProduct
    ) -> ExtensionControllerAssemblyProduct {
        ExtensionControllerAssemblyFactory.make(
            browserConfiguration: controller.browserConfiguration,
            attachment: browser.attachment,
            provisioning: controllerCore.provisioning,
            delegateBridge: controllerCore.delegateBridge,
            callbackAdmission: controllerCore.callbackAdmission,
            permissionPreludes: controllerCore.permissionPreludes,
            nativeMessagingSessions: services.nativeMessagingSessions
        )
    }

    static func makeRuntimeContextResult(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        coordination: ExtensionRuntimeCoordinationPhaseProduct,
        services: ExtensionRuntimeServicePhaseProduct
    ) -> ExtensionContextLifecycleAssemblyProduct {
        ExtensionContextLifecycleAssemblyFactory.make(
            runtime: runtime,
            contexts: contexts,
            contextLoading: contextLoading,
            contextLifecycle: contextLifecycle,
            coordination: coordination,
            services: services
        )
    }

    static func makeRuntimeNormalTabResult(
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        coordination: ExtensionRuntimeCoordinationPhaseProduct,
        services: ExtensionRuntimeServicePhaseProduct,
        browserRoles: ExtensionRuntimeBrowserRolePhaseProduct
    ) -> ExtensionNormalTabAssemblyProduct {
        ExtensionNormalTabAssemblyFactory.make(
            contexts: contexts,
            actions: actions,
            coordination: coordination,
            services: services,
            browserRoles: browserRoles
        )
    }

    static func makeRuntimeActionResult(
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        actionPolicy: ExtensionActionPolicyAssemblyProduct,
        popup: ExtensionPopupAssemblyProduct,
        runtimeAction: ExtensionRuntimeActionPhaseProduct,
        runtimePopup: ExtensionRuntimePopupPhaseProduct
    ) -> ExtensionActionUIAssemblyProduct {
        ExtensionActionUIAssemblyFactory.make(
            contexts: contexts,
            actions: actions,
            actionPolicy: actionPolicy,
            runtimeAction: runtimeAction,
            runtimePopup: runtimePopup
        )
    }

    static func makeRuntimeInstallationResult(
        installation: ExtensionInstallationGraphFoundation,
        retirement: ExtensionRuntimeRetirementAssemblyProduct,
        termination: ExtensionRuntimeTerminationPhaseProduct,
        services: ExtensionRuntimeServicePhaseProduct
    ) -> ExtensionInstallationRetirementAssemblyProduct {
        ExtensionInstallationRetirementAssemblyFactory.make(
            metadataStore: installation.metadataStore,
            catalog: services.catalog,
            lifecycle: services.lifecycle,
            installer: services.installer,
            runtimeRetirement: retirement.runtime,
            runtimeTermination: termination.termination,
            storageCleanup: termination.storageCleanup
        )
    }
}
