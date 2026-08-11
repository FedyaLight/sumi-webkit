import Foundation

@available(macOS 15.5, *)
@MainActor
enum ExtensionControllerAssemblyFactory {
    static func make(
        browserConfiguration: BrowserConfiguration,
        attachment: ExtensionBrowserAttachmentAuthority,
        provisioning: ExtensionControllerProvisioningOwner,
        delegateBridge: ExtensionControllerDelegateBridge,
        callbackAdmission: ExtensionControllerCallbackAdmission,
        permissionPreludes:
            ExtensionPermissionsOriginsCompatibilityPreludeInstallationOwner,
        nativeMessagingSessions: ExtensionNativeMessagingSessionControl
    ) -> ExtensionControllerAssemblyProduct {
        let browserCallbacks =
            ExtensionBrowserAttachmentAuthority.ControllerCallbacks(
                attachment: attachment,
                admission: callbackAdmission
            )
        let lifetime = ExtensionControllerLifetimeOwner(
            browserConfiguration: browserConfiguration,
            provisioning: provisioning,
            delegateBridge: delegateBridge,
            callbackAdmission: callbackAdmission,
            browserCallbacks: browserCallbacks,
            permissionPreludes: permissionPreludes,
            nativeMessagingSessions: nativeMessagingSessions
        )
        return ExtensionControllerAssemblyProduct(
            lifetime: lifetime,
            provisioning: provisioning,
            delegateBridge: delegateBridge,
            callbackAdmission: callbackAdmission,
            browserCallbacks: browserCallbacks,
            permissionPreludes: permissionPreludes,
            nativeMessagingSessions: nativeMessagingSessions
        )
    }
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionContextLifecycleAssemblyFactory {
    static func make(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        coordination: ExtensionRuntimeCoordinationPhaseProduct,
        services: ExtensionRuntimeServicePhaseProduct
    ) -> ExtensionContextLifecycleAssemblyProduct {
        let runtimeLifetime = ExtensionContextRuntimeLifetime(
            moduleRegistry: contexts.moduleRegistry,
            profileRuntime: runtime.profileRuntime,
            lifecycle: runtime.lifecycle,
            demand: runtime.demand,
            loadStatus: runtime.loadStatus,
            catalog: runtime.catalog,
            residency: runtime.residency,
            metrics: runtime.metrics
        )
        let transactionLifetime = ExtensionContextTransactionResidenceOwner(
            loadRevisions: runtime.loadRevisions,
            tabPublicationRevisions: runtime.tabPublicationRevisions,
            mutationRegistry: contexts.runtimeMutationRegistry,
            contextLoadRegistry: contexts.contextLoadRegistry,
            backgroundRuntimeState: contexts.backgroundRuntimeState,
            demandCoordinator: coordination.demandCoordinator
        )
        let publicationLifetime = ExtensionContextPublicationLifetime(
            profileTransition: coordination.profileTransition,
            contextResidency: coordination.contextResidency,
            websiteDataQuiescence: services.websiteDataQuiescence,
            contextPublications: contextLoading.publications,
            profileRuntimeState: contextLifecycle.profileState,
            diagnostics: runtime.diagnostics
        )
        return ExtensionContextLifecycleAssemblyProduct(
            runtimeLifetime: runtimeLifetime,
            transactionLifetime: transactionLifetime,
            publicationLifetime: publicationLifetime,
            runtimeDemand: coordination.demandCoordinator,
            contextPublications: contextLoading.publications,
            profileTransition: coordination.profileTransition,
            contextResidency: coordination.contextResidency,
            websiteDataQuiescence: services.websiteDataQuiescence
        )
    }
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionNormalTabAssemblyFactory {
    static func make(
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        coordination: ExtensionRuntimeCoordinationPhaseProduct,
        services: ExtensionRuntimeServicePhaseProduct,
        browserRoles: ExtensionRuntimeBrowserRolePhaseProduct
    ) -> ExtensionNormalTabAssemblyProduct {
        let preparationLifetime = ExtensionNormalTabPreparationLifetime(
            configurationPreparation: services.webViewConfiguration,
            deferredRuntimeOwners: coordination.deferredRuntimeOwners,
            recentTabRequests: contexts.recentTabRequests,
            requestedTabLoadResolver: contexts.requestedTabLoadResolver,
            adapterStore: actions.adapterStore
        )
        let publicationLifetime = ExtensionNormalTabPublicationLifetime(
            publicationEvidence: services.publicationEvidence,
            lifecycle: browserRoles.normalTabLifecycle,
            requestedTabs: browserRoles.requestedTabs,
            query: browserRoles.normalTabQuery
        )
        return ExtensionNormalTabAssemblyProduct(
            preparationLifetime: preparationLifetime,
            publicationLifetime: publicationLifetime,
            configurationPreparation: services.webViewConfiguration,
            deferredRuntimeOwners: coordination.deferredRuntimeOwners,
            publicationEvidence: services.publicationEvidence,
            lifecycle: browserRoles.normalTabLifecycle,
            requestedTabs: browserRoles.requestedTabs,
            query: browserRoles.normalTabQuery
        )
    }
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionActionUIAssemblyFactory {
    static func make(
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        actionPolicy: ExtensionActionPolicyAssemblyProduct,
        runtimeAction: ExtensionRuntimeActionPhaseProduct,
        runtimePopup: ExtensionRuntimePopupPhaseProduct,
        runtimeKeyboard: ExtensionRuntimeKeyboardPhaseProduct
    ) -> ExtensionActionUIAssemblyProduct {
        let surfaceLifetime = ExtensionActionSurfaceResidenceOwner(
            installedExtensions: contexts.installedExtensions,
            surfacePublication: actions.surfacePublication,
            actionSurfacePublisher: actionPolicy.actionSurfaces,
            actionInvocation: runtimeAction.actionInvocation
        )
        let policyLifetime = ExtensionActionPolicyResidenceOwner(
            toolbarPinning: actionPolicy.toolbarPinning,
            hubOrdering: actionPolicy.hubOrdering,
            siteAccess: actionPolicy.siteAccess,
            permissionDecisions: actionPolicy.permissionDecisions,
            permissionPrompt: actionPolicy.permissionPrompt
        )
        let popupLifetime = ExtensionActionPopupResidenceOwner(
            actionAnchors: actions.actionAnchors,
            popupAnchors: actions.actionPopupAnchors,
            popupInvocations: actions.actionPopupInvocations,
            popupSessions: actions.actionPopupSessions,
            popupCallbackAdmission: runtimePopup.callbackAdmission
        )
        let presentationLifetime = ExtensionActionPresentationResidenceOwner(
            popupCoordinator: runtimePopup.coordinator,
            popupAnchorResolver: runtimePopup.anchorResolver,
            optionsWindows: actions.optionsWindows,
            keyboardCommands: runtimeKeyboard.keyboardCommands
        )
        return ExtensionActionUIAssemblyProduct(
            surfaceLifetime: surfaceLifetime,
            policyLifetime: policyLifetime,
            popupLifetime: popupLifetime,
            presentationLifetime: presentationLifetime,
            surface: ExtensionActionSurfaceAssemblyProduct(
                publisher: actionPolicy.actionSurfaces,
                invocation: runtimeAction.actionInvocation,
                toolbarPinning: actionPolicy.toolbarPinning,
                hubOrdering: actionPolicy.hubOrdering,
                siteAccess: actionPolicy.siteAccess
            ),
            presentation: ExtensionActionPresentationAssemblyProduct(
                popupCallbackAdmission: runtimePopup.callbackAdmission,
                popupCoordinator: runtimePopup.coordinator,
                popupAnchorResolver: runtimePopup.anchorResolver,
                keyboardCommands: runtimeKeyboard.keyboardCommands
            )
        )
    }
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionInstallationRetirementAssemblyFactory {
    static func make(
        metadataStore: ExtensionInstallationMetadataStore,
        catalog: InstalledExtensionCatalog,
        lifecycle: InstalledExtensionLifecycleService,
        installer: ExtensionInstallationService,
        runtimeRetirement: ExtensionRuntimeRetirement,
        runtimeTermination: ExtensionRuntimeTermination,
        storageCleanup: WebExtensionStorageCleanupOwner
    ) -> ExtensionInstallationRetirementAssemblyProduct {
        let lifetime = ExtensionInstallationRetirementLifetimeOwner(
            metadataStore: metadataStore,
            catalog: catalog,
            lifecycle: lifecycle,
            installer: installer,
            runtimeRetirement: runtimeRetirement,
            runtimeTermination: runtimeTermination,
            storageCleanup: storageCleanup
        )
        return ExtensionInstallationRetirementAssemblyProduct(
            lifetime: lifetime,
            catalog: catalog,
            lifecycle: lifecycle,
            installer: installer,
            runtimeTermination: runtimeTermination
        )
    }
}

@available(macOS 15.5, *)
@MainActor
enum ExtensionRuntimePublicationGraphFactory {
    static func make(
        attachment: ExtensionBrowserAttachmentAuthority,
        browserEvents: ExtensionBrowserAttachmentAuthority.BrowserEvents,
        reloads: ExtensionBrowserAttachmentAuthority.Reloads,
        attacher: ExtensionBrowserRuntimeAttacher
    ) -> ExtensionRuntimePublicationGraph {
        ExtensionRuntimePublicationGraph(
            lifetime: ExtensionRuntimePublicationLifetimeOwner(
                attachment: attachment,
                browserEvents: browserEvents,
                reloads: reloads,
                attacher: attacher
            ),
            attacher: attacher
        )
    }
}
