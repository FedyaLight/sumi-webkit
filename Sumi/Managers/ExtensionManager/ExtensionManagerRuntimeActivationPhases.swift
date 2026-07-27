import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionContextFinalizationPhaseProduct {
    let installActivation: ExtensionInstallRuntimeActivator
    let finalizer: ExtensionLoadedContextFinalizer
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeActivationPhaseProduct {
    let installationActivator: ExtensionInstallRuntimeActivator
    let installation: ExtensionInstallationRuntimeActivation
    let enabled: ExtensionEnabledRuntimeActivation
    let recovery: ExtensionRuntimeRecovery
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleContextFinalizationPhase(
        browser: ExtensionManagerBrowserFoundation,
        actionPolicy: ExtensionActionPolicyAssemblyProduct,
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        nativeMessaging: ExtensionNativeMessagingAssemblyProduct,
        bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission
    ) -> ExtensionContextFinalizationPhaseProduct {
        let installActivation = ExtensionInstallRuntimeActivator(
            authority: contextLoading.authority,
            backgroundWakes: nativeMessaging.backgroundWakes,
            reloadPublications: { [reloads = browser.reloads] reason, profileID in
                reloads.finalizeRuntimeLoad(
                    reason: reason,
                    profileID: profileID
                )
            }
        )
        return ExtensionContextFinalizationPhaseProduct(
            installActivation: installActivation,
            finalizer: ExtensionLoadedContextFinalizer(
                authority: contextLoading.authority,
                actionSurfaces: actionPolicy.actionSurfaces,
                retention: contextLifecycle.retention,
                settlement: contextLifecycle.settlement,
                installationActivation: installActivation,
                bootstrapChromeAdmission: bootstrapChromeAdmission
            )
        )
    }

    static func assembleRuntimeLoaderPhase(
        installation: ExtensionInstallationGraphFoundation,
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        controller: ExtensionControllerCoreAssemblyProduct,
        retirement: ExtensionRuntimeRetirementAssemblyProduct,
        contextLoader: ExtensionContextLoader,
        finalization: ExtensionContextFinalizationPhaseProduct
    ) -> ExtensionRuntimeLoader {
        ExtensionRuntimeLoader(
            metadataStore: installation.metadataStore,
            installedRecords: contexts.installedExtensions,
            runtimeAccess: controller.runtimeAccess,
            runtimeCatalog: runtime.catalog,
            runtimeMetrics: runtime.metrics,
            authority: contextLoading.authority,
            rollback: retirement.rollback,
            contextLoader: contextLoader,
            finalizer: finalization.finalizer,
            diagnostics: runtime.diagnostics
        )
    }

    static func assembleRuntimeActivationPhase(
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        controller: ExtensionControllerCoreAssemblyProduct,
        retirement: ExtensionRuntimeRetirementAssemblyProduct,
        contextLoader: ExtensionContextLoader,
        finalization: ExtensionContextFinalizationPhaseProduct,
        runtimeLoader: ExtensionRuntimeLoader
    ) -> ExtensionRuntimeActivationPhaseProduct {
        let installation = ExtensionInstallationRuntimeActivation(
            runtimeAccess: controller.runtimeAccess,
            authority: contextLoading.authority,
            rollback: retirement.rollback,
            contextLoader: contextLoader,
            activation: finalization.installActivation,
            settlement: contextLifecycle.settlement
        )
        let enabled = ExtensionEnabledRuntimeActivation(
            runtimeAccess: controller.runtimeAccess,
            authority: contextLoading.authority,
            loader: runtimeLoader,
            finalizer: finalization.finalizer
        )
        return ExtensionRuntimeActivationPhaseProduct(
            installationActivator: finalization.installActivation,
            installation: installation,
            enabled: enabled,
            recovery: ExtensionRuntimeRecovery(activation: enabled)
        )
    }
}
