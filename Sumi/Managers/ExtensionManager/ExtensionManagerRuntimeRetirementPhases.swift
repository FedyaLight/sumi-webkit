import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeBookkeepingPhaseProduct {
    let activityCancellation: ExtensionRuntimeActivityCancellation
    let bookkeepingReset: ExtensionRuntimeBookkeepingReset
    let controllerRelease: ExtensionControllerRuntimeRelease
    let storageCleanup: WebExtensionStorageCleanupOwner
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeShutdownPhaseProduct {
    let bookkeeping: ExtensionRuntimeBookkeepingPhaseProduct
    let shutdown: ExtensionRuntimeShutdown
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeTerminationPhaseProduct {
    let activityCancellation: ExtensionRuntimeActivityCancellation
    let bookkeepingReset: ExtensionRuntimeBookkeepingReset
    let controllerRelease: ExtensionControllerRuntimeRelease
    let shutdown: ExtensionRuntimeShutdown
    let termination: ExtensionRuntimeTermination
    let storageCleanup: WebExtensionStorageCleanupOwner
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleRuntimeBookkeepingPhase(
        installation: ExtensionInstallationGraphFoundation,
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        controller: ExtensionControllerGraphFoundation,
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        controllerCore: ExtensionControllerCoreAssemblyProduct
    ) -> ExtensionRuntimeBookkeepingPhaseProduct {
        let storageCleanup = WebExtensionStorageCleanupOwner(
            profileRuntime: runtime.profileRuntime,
            installedExtensions: contexts.installedExtensions,
            diagnostics: runtime.diagnostics,
            resolvedProfileID: {
                [profileRuntime = runtime.profileRuntime] explicit in
                explicit
                    ?? profileRuntime.currentProfileId
                    ?? profileRuntime.currentRememberedProfile?.id
            },
            controllerStorageID: {
                ExtensionProfileControllerIdentity.runtimeIdentifier(for: $0)
            },
            persistentProfileIDs: {
                try installation.database.read {
                    try $0.profiles.all().map(\.id)
                }
            },
            controllerForProfile: {
                controllerCore.provisioning.controllerIfAdmitted(for: $0)
            }
        )
        #if DEBUG
            storageCleanup.installDebugDataCleanup {
                [debug = actions.debugSignals] in
                debug.webExtensionDataCleanup
            }
        #endif
        return ExtensionRuntimeBookkeepingPhaseProduct(
            activityCancellation: ExtensionRuntimeActivityCancellation(
                loadRegistry: contexts.contextLoadRegistry,
                backgroundRuntimeState: contexts.backgroundRuntimeState,
                nativeMessagingPorts: controller.nativeMessagingPorts,
                diagnostics: runtime.diagnostics
            ),
            bookkeepingReset: ExtensionRuntimeBookkeepingReset(
                runtimeCatalog: runtime.catalog,
                runtimeResidency: runtime.residency,
                runtimeMetrics: runtime.metrics,
                sourceCache: contextLoading.sourceCache,
                backgroundRuntimeState: contexts.backgroundRuntimeState,
                errorObservation: contextLifecycle.errors,
                recentTabRequests: contexts.recentTabRequests,
                permissionPreludes: controllerCore.permissionPreludes,
                controllerProvisioning: controllerCore.provisioning,
                adapterStore: actions.adapterStore,
                optionsWindows: actions.optionsWindows,
                actionAnchors: actions.actionAnchors,
                actionPopupAnchors: actions.actionPopupAnchors,
                actionPopupInvocations: actions.actionPopupInvocations
            ),
            controllerRelease: ExtensionControllerRuntimeRelease(
                runtimeLifecycle: runtime.lifecycle,
                runtimeDemand: runtime.demand,
                controllerDelegateReadiness: controllerCore.delegateReadiness,
                controllerProvisioning: controllerCore.provisioning
            ),
            storageCleanup: storageCleanup
        )
    }

    static func assembleRuntimeShutdownPhase(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        controller: ExtensionControllerGraphFoundation,
        contextLoading: ExtensionContextLoadingAssemblyProduct,
        contextLifecycle: ExtensionContextLifecycleCoreProduct,
        retirement: ExtensionRuntimeRetirementAssemblyProduct,
        bookkeeping: ExtensionRuntimeBookkeepingPhaseProduct
    ) -> ExtensionRuntimeShutdownPhaseProduct {
        ExtensionRuntimeShutdownPhaseProduct(
            bookkeeping: bookkeeping,
            shutdown: ExtensionRuntimeShutdown(
                activityCancellation: bookkeeping.activityCancellation,
                mutationRegistry: contexts.runtimeMutationRegistry,
                scopedRetirement: retirement.scoped,
                bookkeepingReset: bookkeeping.bookkeepingReset,
                controllerRelease: bookkeeping.controllerRelease,
                profileRuntime: runtime.profileRuntime,
                runtimeLifecycle: runtime.lifecycle,
                runtimeCatalog: runtime.catalog,
                extensionLoadRevisions: runtime.loadRevisions,
                sourceCache: contextLoading.sourceCache,
                errorObservation: contextLifecycle.errors,
                optionsWindows: actions.optionsWindows,
                actionAnchors: actions.actionAnchors,
                nativeMessagingPorts: controller.nativeMessagingPorts,
                diagnostics: runtime.diagnostics
            )
        )
    }

    static func assembleRuntimeTerminationPhase(
        actions: ExtensionActionGraphFoundation,
        browser: ExtensionManagerBrowserFoundation,
        nativeMessaging: ExtensionNativeMessagingAssemblyProduct,
        coordination: ExtensionRuntimeCoordinationPhaseProduct,
        shutdown: ExtensionRuntimeShutdownPhaseProduct
    ) -> ExtensionRuntimeTerminationPhaseProduct {
        let termination = ExtensionRuntimeTermination(
            shutdown: shutdown.shutdown,
            browser: browser.retirement,
            deferredOwners: coordination.deferredRuntimeOwners,
            profileWarmup: coordination.profileWarmup,
            nativeMessagingOwners: nativeMessaging.owners,
            surfacePublication: actions.surfacePublication
        )
        return ExtensionRuntimeTerminationPhaseProduct(
            activityCancellation:
                shutdown.bookkeeping.activityCancellation,
            bookkeepingReset: shutdown.bookkeeping.bookkeepingReset,
            controllerRelease: shutdown.bookkeeping.controllerRelease,
            shutdown: shutdown.shutdown,
            termination: termination,
            storageCleanup: shutdown.bookkeeping.storageCleanup
        )
    }
}
