import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeDemandPhaseProduct {
    let deferredOwners: ExtensionDeferredRuntimeOwnerStore
    let coordinator: ExtensionRuntimeDemandCoordinator
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeCoordinationPhaseProduct {
    let contextResidency: ExtensionContextResidencyOwner
    let deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore
    let demandCoordinator: ExtensionRuntimeDemandCoordinator
    let profileTransition: ExtensionProfileRuntimeTransition
    let profileWarmup: ExtensionProfileRuntimeWarmup
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleContextResidencyPhase(
        installation: ExtensionInstallationGraphFoundation,
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        controller: ExtensionControllerCoreAssemblyProduct,
        runtimeLoader: ExtensionRuntimeLoader
    ) -> ExtensionContextResidencyOwner {
        let loading = ExtensionContextLoadingOwner(
            installedExtensions: contexts.installedExtensions,
            runtimeAccess: controller.runtimeAccess,
            metadataStore: installation.metadataStore,
            retention: contextLifecycle.retention,
            runtimeIsEnabled: { [modules = contexts.moduleRegistry] in
                modules.isEnabledForRuntimeBoundary(.extensions)
            },
            loader: runtimeLoader
        )
        return ExtensionContextResidencyOwner(
            retention: contextLifecycle.retention,
            loading: loading,
            settlement: contextLifecycle.settlement
        )
    }

    static func assembleRuntimeDemandPhase(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        controller: ExtensionControllerCoreAssemblyProduct,
        nativeMessaging: ExtensionNativeMessagingAssemblyProduct,
        contextResidency: ExtensionContextResidencyOwner
    ) -> ExtensionRuntimeDemandPhaseProduct {
        ExtensionRuntimeDemandPhaseProduct(
            deferredOwners: ExtensionDeferredRuntimeOwnerStore(
                installedExtensions: contexts.installedExtensions,
                runtimeCatalog: runtime.catalog,
                runtimeQuery: ExtensionDeferredRuntimeQuery(
                    modules: contexts.moduleRegistry
                ),
                profileQuery: runtime.profileRuntime,
                contextLoading: contextResidency,
                backgroundWake: nativeMessaging.backgroundWakes,
                failureLogger: ExtensionDeferredRuntimeFailureLogger()
            ),
            coordinator: ExtensionRuntimeDemandCoordinator(
                installedExtensions: contexts.installedExtensions,
                profileRuntime: runtime.profileRuntime,
                runtimeLifecycle: runtime.lifecycle,
                runtimeDemand: runtime.demand,
                controllerProvisioning: controller.provisioning,
                runtimeProfileID: { [profileRuntime = runtime.profileRuntime] in
                    profileRuntime.currentProfileId
                        ?? profileRuntime.currentRememberedProfile?.id
                },
                diagnostics: runtime.diagnostics
            )
        )
    }

    static func assembleProfileTransitionPhase(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        controller: ExtensionControllerGraphFoundation,
        browser: ExtensionManagerBrowserFoundation,
        actionPolicy: ExtensionActionPolicyAssemblyProduct,
        controllerCore: ExtensionControllerCoreAssemblyProduct,
        contextResidency: ExtensionContextResidencyOwner
    ) -> ExtensionProfileRuntimeTransition {
        ExtensionProfileRuntimeTransition(
                readinessProbe: ExtensionProfileReadinessProbe(
                    installedExtensions: contexts.installedExtensions,
                    profileRuntime: runtime.profileRuntime,
                    runtimeLifecycle: runtime.lifecycle
                ),
                transitionLease: ExtensionProfileTransitionLease(
                    profileRuntime: runtime.profileRuntime
                ),
                profileRuntime: runtime.profileRuntime,
                runtimeLifecycle: runtime.lifecycle,
                browserConfiguration: controller.browserConfiguration,
                controllerProvisioning: controllerCore.provisioning,
                surfaceHandoff: ExtensionProfileSurfaceHandoff(
                    actionAnchors: actions.actionPopupAnchors,
                    toolbarProfiles: actionPolicy.toolbarPinning,
                    browserConfiguration: controller.browserConfiguration,
                    profileRuntime: runtime.profileRuntime,
                    inactiveContextRetirement: contextResidency
                ),
                reconcileProfile: { [reloads = browser.reloads] profileID in
                    reloads.reconcile(
                        profileID: profileID,
                        reason: "ExtensionProfileRuntimeTransition"
                    )
                },
                refreshActionSurfaces: {
                    [profileRuntime = runtime.profileRuntime,
                     actionSurfaces = actionPolicy.actionSurfaces]
                    profileID in
                    guard profileRuntime.currentProfileId == profileID else {
                        return
                    }
                    for context in profileRuntime.contexts(for: profileID).values {
                        guard profileRuntime.currentProfileId == profileID else {
                            return
                        }
                        actionSurfaces
                            .publishActionSurfaceStateForLoadedContext(context)
                    }
                }
        )
    }

    static func assembleRuntimeCoordinationPhase(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        contextResidency: ExtensionContextResidencyOwner,
        demand: ExtensionRuntimeDemandPhaseProduct,
        profileTransition: ExtensionProfileRuntimeTransition
    ) -> ExtensionRuntimeCoordinationPhaseProduct {
        ExtensionRuntimeCoordinationPhaseProduct(
            contextResidency: contextResidency,
            deferredRuntimeOwners: demand.deferredOwners,
            demandCoordinator: demand.coordinator,
            profileTransition: profileTransition,
            profileWarmup: ExtensionProfileRuntimeWarmup(
                readiness: ExtensionProfileReadinessProbe(
                    installedExtensions: contexts.installedExtensions,
                    profileRuntime: runtime.profileRuntime,
                    runtimeLifecycle: runtime.lifecycle
                ),
                residency: contextResidency,
                profileRuntime: runtime.profileRuntime,
                runtimeIsEnabled: { [modules = contexts.moduleRegistry] in
                    modules.isEnabledForRuntimeBoundary(.extensions)
                }
            )
        )
    }
}
