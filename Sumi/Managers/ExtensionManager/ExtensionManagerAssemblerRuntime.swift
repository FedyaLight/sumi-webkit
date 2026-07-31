import Foundation

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleRuntime(
        _ f: ExtensionManagerAssemblyFoundation,
        core: ExtensionManagerCoreAssembly
    ) -> ExtensionManagerAssemblyResult {
        let transaction = assembleContextControllerTransactionPhase(
            runtime: f.runtime, actions: f.actions,
            contextLoading: core.contextLoading,
            contextLifecycle: core.contextLifecycle,
            controller: core.controller, retirement: core.retirement
        )
        let contextLoader = assembleContextLoaderPhase(
            runtime: f.runtime, contexts: f.contexts, browser: f.browser,
            actionPolicy: core.actionPolicy,
            contextLoading: core.contextLoading, controller: core.controller,
            transaction: transaction,
            bootstrapChromeAdmission: core.bootstrapChromeAdmission
        )
        let finalization = assembleContextFinalizationPhase(
            browser: f.browser, actionPolicy: core.actionPolicy,
            contextLoading: core.contextLoading,
            contextLifecycle: core.contextLifecycle,
            nativeMessaging: core.nativeMessaging,
            bootstrapChromeAdmission: core.bootstrapChromeAdmission
        )
        let runtimeLoader = assembleRuntimeLoaderPhase(
            installation: f.installation, runtime: f.runtime,
            contexts: f.contexts, contextLoading: core.contextLoading,
            controller: core.controller, retirement: core.retirement,
            contextLoader: contextLoader, finalization: finalization
        )
        let activation = assembleRuntimeActivationPhase(
            contextLoading: core.contextLoading,
            contextLifecycle: core.contextLifecycle,
            controller: core.controller, retirement: core.retirement,
            contextLoader: contextLoader, finalization: finalization,
            runtimeLoader: runtimeLoader
        )
        let residency = assembleContextResidencyPhase(
            installation: f.installation, runtime: f.runtime,
            contexts: f.contexts,
            contextLifecycle: core.contextLifecycle,
            controller: core.controller, runtimeLoader: runtimeLoader
        )
        let demand = assembleRuntimeDemandPhase(
            runtime: f.runtime, contexts: f.contexts,
            controller: core.controller,
            nativeMessaging: core.nativeMessaging,
            contextResidency: residency
        )
        let profileTransition = assembleProfileTransitionPhase(
            runtime: f.runtime, contexts: f.contexts, actions: f.actions,
            controller: f.controller, browser: f.browser,
            actionPolicy: core.actionPolicy,
            controllerCore: core.controller, contextResidency: residency
        )
        let coordination = assembleRuntimeCoordinationPhase(
            runtime: f.runtime, contexts: f.contexts,
            contextResidency: residency, demand: demand, profileTransition: profileTransition
        )
        let popupCoordination = assemblePopupCoordinationPhase(
            contexts: f.contexts, actions: f.actions, browser: f.browser,
            controller: core.controller, popup: core.popup
        )
        let popupDiagnostics = assemblePopupDiagnosticsPhase(
            installation: f.installation, runtime: f.runtime,
            contexts: f.contexts,
            contextLifecycle: core.contextLifecycle
        )
        let runtimePopup = assembleRuntimePopupPhase(
            runtime: f.runtime, contextLifecycle: core.contextLifecycle,
            popup: core.popup, coordination: coordination,
            popupCoordination: popupCoordination,
            diagnostics: popupDiagnostics
        )
        let runtimeAction = assembleRuntimeActionPhase(
            runtime: f.runtime, contexts: f.contexts, actions: f.actions,
            browser: f.browser, actionPolicy: core.actionPolicy,
            controller: core.controller, coordination: coordination,
            runtimePopup: runtimePopup
        )
        let bookkeeping = assembleRuntimeBookkeepingPhase(
            installation: f.installation, runtime: f.runtime,
            contexts: f.contexts, actions: f.actions,
            controller: f.controller, contextLoading: core.contextLoading,
            contextLifecycle: core.contextLifecycle,
            controllerCore: core.controller
        )
        let shutdown = assembleRuntimeShutdownPhase(
            runtime: f.runtime, contexts: f.contexts, actions: f.actions,
            controller: f.controller, contextLoading: core.contextLoading,
            contextLifecycle: core.contextLifecycle,
            retirement: core.retirement, bookkeeping: bookkeeping
        )
        let termination = assembleRuntimeTerminationPhase(
            actions: f.actions, browser: f.browser,
            nativeMessaging: core.nativeMessaging,
            coordination: coordination, shutdown: shutdown
        )
        let browserSupport = assembleRuntimeBrowserSupportPhase(
            runtime: f.runtime, contexts: f.contexts, actions: f.actions,
            controller: f.controller, popup: core.popup,
            controllerCore: core.controller,
            nativeMessaging: core.nativeMessaging,
            coordination: coordination
        )
        let catalog = assembleRuntimeCatalogPhase(
            installation: f.installation, runtime: f.runtime,
            contexts: f.contexts, actions: f.actions
        )
        let lifecycle = assembleRuntimeLifecyclePhase(
            installation: f.installation, contexts: f.contexts,
            actions: f.actions,
            controller: core.controller, retirement: core.retirement,
            activation: activation, termination: termination,
            bootstrapChromeAdmission: core.bootstrapChromeAdmission
        )
        let installer = assembleRuntimeInstallerPhase(
            installation: f.installation, runtime: f.runtime,
            contexts: f.contexts, actions: f.actions,
            retirement: core.retirement, coordination: coordination,
            activation: activation, termination: termination
        )
        let services = assembleRuntimeServicePhase(
            browserSupport: browserSupport, catalog: catalog,
            lifecycle: lifecycle, installer: installer
        )
        let browserRoles = assembleRuntimeBrowserRolePhase(
            runtime: f.runtime, browser: f.browser,
            coordination: coordination
        )
        #if DEBUG
            ExtensionManagerRuntimeTestInspector.publish(
                core.inspectionDidAssemble,
                foundation: f,
                core: core,
                runtimeLoader: runtimeLoader,
                activation: activation,
                coordination: coordination,
                popup: runtimePopup,
                action: runtimeAction,
                termination: termination,
                services: services,
                browserRoles: browserRoles
            )
        #endif
        return ExtensionManagerAssemblyResult(
            profileWarmup: coordination.profileWarmup,
            controller: makeRuntimeControllerResult(
                controller: f.controller, browser: f.browser,
                controllerCore: core.controller, services: services
            ),
            contexts: makeRuntimeContextResult(
                runtime: f.runtime, contexts: f.contexts,
                contextLoading: core.contextLoading,
                contextLifecycle: core.contextLifecycle,
                coordination: coordination, services: services
            ),
            normalTabs: makeRuntimeNormalTabResult(
                contexts: f.contexts, actions: f.actions,
                coordination: coordination, services: services,
                browserRoles: browserRoles
            ),
            actions: makeRuntimeActionResult(
                contexts: f.contexts, actions: f.actions,
                actionPolicy: core.actionPolicy, popup: core.popup,
                runtimeAction: runtimeAction, runtimePopup: runtimePopup
            ),
            installation: makeRuntimeInstallationResult(
                installation: f.installation, retirement: core.retirement,
                termination: termination, services: services
            )
        )
    }
}
