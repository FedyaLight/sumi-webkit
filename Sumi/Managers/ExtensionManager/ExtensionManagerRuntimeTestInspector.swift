#if DEBUG
    import Foundation

    @available(macOS 15.5, *)
    @MainActor
    enum ExtensionManagerRuntimeTestInspector {
        static func publish(
            _ didAssemble: ExtensionManagerTestInspection.DidAssemble?,
            foundation f: ExtensionManagerAssemblyFoundation,
            core: ExtensionManagerCoreAssembly,
            runtimeLoader: ExtensionRuntimeLoader,
            activation: ExtensionRuntimeActivationPhaseProduct,
            coordination: ExtensionRuntimeCoordinationPhaseProduct,
            popup: ExtensionRuntimePopupPhaseProduct,
            action: ExtensionRuntimeActionPhaseProduct,
            termination: ExtensionRuntimeTerminationPhaseProduct,
            services: ExtensionRuntimeServicePhaseProduct,
            browserRoles: ExtensionRuntimeBrowserRolePhaseProduct
        ) {
            didAssemble?(
                ExtensionManagerTestInspection(
                    controller: .init(
                        browserConfiguration: f.controller.browserConfiguration,
                        provisioning: core.controller.provisioning,
                        delegateBridge: core.controller.delegateBridge,
                        callbackAdmission: core.controller.callbackAdmission,
                        delegateReadiness: core.controller.delegateReadiness,
                        permissionPreludes: core.controller.permissionPreludes
                    ),
                    contextState: .init(
                        profiles: f.runtime.profileRuntime,
                        profileState: core.contextLifecycle.profileState,
                        publications: core.contextLoading.publications,
                        loadedContexts: core.contextLoading.authority,
                        errors: core.contextLifecycle.errors,
                        background: f.contexts.backgroundRuntimeState,
                        sourceCache: core.contextLoading.sourceCache,
                        retirement: core.contextLifecycle.retirement
                    ),
                    runtimeAuthorities: .init(
                        lifecycle: f.runtime.lifecycle,
                        demand: f.runtime.demand,
                        loadStatus: f.runtime.loadStatus,
                        catalog: f.runtime.catalog,
                        residency: f.runtime.residency,
                        metrics: f.runtime.metrics,
                        loadRevisions: f.runtime.loadRevisions,
                        tabPublicationRevisions:
                            f.runtime.tabPublicationRevisions
                    ),
                    contextCoordination: .init(
                        mutations: f.contexts.runtimeMutationRegistry,
                        loads: f.contexts.contextLoadRegistry,
                        demand: coordination.demandCoordinator,
                        profileTransition: coordination.profileTransition,
                        residency: coordination.contextResidency,
                        loader: runtimeLoader,
                        diagnostics: f.runtime.diagnostics,
                        runtimeAccess: core.controller.runtimeAccess
                    ),
                    normalTabs: .init(
                        configuration: services.webViewConfiguration,
                        deferredRuntime: coordination.deferredRuntimeOwners,
                        recentRequests: f.contexts.recentTabRequests,
                        loadResolver: f.contexts.requestedTabLoadResolver,
                        adapters: f.actions.adapterStore,
                        publicationEvidence: services.publicationEvidence,
                        requestedTabs: browserRoles.requestedTabs
                    ),
                    actionSurfaces: .init(
                        installedExtensions: f.contexts.installedExtensions,
                        publication: f.actions.surfacePublication,
                        publisher: core.actionPolicy.actionSurfaces,
                        invocation: action.actionInvocation,
                        toolbarPinning: core.actionPolicy.toolbarPinning,
                        hubOrdering: core.actionPolicy.hubOrdering,
                        keyboardCommands: action.keyboardCommands,
                        optionsWindows: f.actions.optionsWindows
                    ),
                    actionPolicy: .init(
                        store: f.actions.siteAccessPolicyStore,
                        siteAccess: core.actionPolicy.siteAccess,
                        permissionDecisions: core.actionPolicy.permissionDecisions,
                        permissionPrompt: core.actionPolicy.permissionPrompt,
                        contextPreparation: core.actionPolicy.contextPreparation,
                        popupFailureDiagnostics: popup.failureDiagnostics
                    ),
                    popups: .init(
                        actionAnchors: f.actions.actionAnchors,
                        anchors: f.actions.actionPopupAnchors,
                        invocations: f.actions.actionPopupInvocations,
                        sessions: f.actions.actionPopupSessions,
                        callbackAdmission: popup.callbackAdmission,
                        coordinator: popup.coordinator,
                        anchorResolver: popup.anchorResolver,
                        runtimeRetirement: core.popup.runtimeRetirement
                    ),
                    installation: .init(
                        metadata: f.installation.metadataStore,
                        catalog: services.catalog,
                        lifecycle: services.lifecycle,
                        installer: services.installer,
                        runtimeActivation: activation.installationActivator,
                        storageCleanup: termination.storageCleanup,
                        storagePlanner: f.contexts.storageCleanupPlanner
                    ),
                    retirement: .init(
                        scoped: core.retirement.scoped,
                        runtime: core.retirement.runtime,
                        rollback: core.retirement.rollback,
                        activityCancellation:
                            termination.activityCancellation,
                        bookkeepingReset: termination.bookkeepingReset,
                        controllerRelease: termination.controllerRelease,
                        shutdown: termination.shutdown,
                        termination: termination.termination
                    ),
                    nativeMessaging: .init(
                        ports: f.controller.nativeMessagingPorts,
                        owners: core.nativeMessaging.owners,
                        backgroundWakes: core.nativeMessaging.backgroundWakes,
                        messageSettlement:
                            core.nativeMessaging.messageSettlement,
                        portSettlement: core.nativeMessaging.portSettlement,
                        sessions: services.nativeMessagingSessions
                    ),
                    browserPublication: .init(
                        events: f.browser.events,
                        reloads: f.browser.reloads
                    )
                )
            )
        }
    }
#endif
