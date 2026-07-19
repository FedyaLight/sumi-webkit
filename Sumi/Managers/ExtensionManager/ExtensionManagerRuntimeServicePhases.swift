import Foundation

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeBrowserSupportPhaseProduct {
    let webViewConfiguration: ExtensionWebViewConfigurationPreparation
    let publicationEvidence: ExtensionRuntimePublicationEvidenceIssuer
    let websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence
    let nativeMessagingSessions: ExtensionNativeMessagingSessionControl
}

@available(macOS 15.5, *)
@MainActor
struct ExtensionRuntimeServicePhaseProduct {
    let webViewConfiguration: ExtensionWebViewConfigurationPreparation
    let catalog: InstalledExtensionCatalog
    let lifecycle: InstalledExtensionLifecycleService
    let installer: ExtensionInstallationService
    let publicationEvidence: ExtensionRuntimePublicationEvidenceIssuer
    let websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence
    let nativeMessagingSessions: ExtensionNativeMessagingSessionControl
}

@available(macOS 15.5, *)
@MainActor
extension ExtensionManagerAssembler {
    static func assembleRuntimeBrowserSupportPhase(
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        controller: ExtensionControllerGraphFoundation,
        popup: ExtensionPopupAssemblyProduct,
        controllerCore: ExtensionControllerCoreAssemblyProduct,
        nativeMessaging: ExtensionNativeMessagingAssemblyProduct,
        coordination: ExtensionRuntimeCoordinationPhaseProduct
    ) -> ExtensionRuntimeBrowserSupportPhaseProduct {
        ExtensionRuntimeBrowserSupportPhaseProduct(
            webViewConfiguration: ExtensionWebViewConfigurationPreparation(
                provisioning: controllerCore.provisioning,
                preludes: controllerCore.permissionPreludes,
                resolveProfileID: { [profileRuntime = runtime.profileRuntime] explicit in
                    explicit
                        ?? profileRuntime.currentProfileId
                        ?? profileRuntime.currentRememberedProfile?.id
                },
                requestRuntime: {
                    [demand = coordination.demandCoordinator] profileID in
                    _ = demand.requestRuntimeIfDemanded(
                        reason: .webViewConfiguration,
                        profileId: profileID
                    )
                },
                diagnostics: runtime.diagnostics
            ),
            publicationEvidence: ExtensionRuntimePublicationEvidenceIssuer(
                extensionLoadRevisions: runtime.loadRevisions,
                tabPublicationRevisions: runtime.tabPublicationRevisions
            ),
            websiteDataQuiescence: ExtensionWebsiteDataRuntimeQuiescence(
                optionsWindows: actions.optionsWindows,
                popupRetirement: popup.retirement,
                contextResidency: coordination.contextResidency
            ),
            nativeMessagingSessions: ExtensionNativeMessagingSessionControl(
                ports: controller.nativeMessagingPorts,
                owners: nativeMessaging.owners,
                diagnostics: runtime.diagnostics
            )
        )
    }

    static func assembleRuntimeCatalogPhase(
        installation: ExtensionInstallationGraphFoundation,
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation
    ) -> InstalledExtensionCatalog {
        InstalledExtensionCatalog(
            environment: .init(
                metadataStore: installation.metadataStore,
                installedRecords: contexts.installedExtensions,
                volatileRecords: makeVolatileRecordReconciler(
                    installation: installation,
                    contexts: contexts
                ),
                liveContextCount: { [profileRuntime = runtime.profileRuntime] in
                    profileRuntime.countLoadedExtensionContexts()
                },
                markCatalogLoaded: { [surface = actions.surfacePublication] in
                    _ = surface.markRuntimePublicationReady()
                },
                trace: { [diagnostics = runtime.diagnostics] in
                    diagnostics.trace($0)
                }
            )
        )
    }

    static func assembleRuntimeLifecyclePhase(
        installation: ExtensionInstallationGraphFoundation,
        contexts: ExtensionContextGraphFoundation,
        controller: ExtensionControllerCoreAssemblyProduct,
        retirement: ExtensionRuntimeRetirementAssemblyProduct,
        activation: ExtensionRuntimeActivationPhaseProduct,
        termination: ExtensionRuntimeTerminationPhaseProduct,
        bootstrapChromeAdmission: ExtensionBootstrapChromeAdmission
    ) -> InstalledExtensionLifecycleService {
        InstalledExtensionLifecycleService(
            environment: .init(
                    modelContext: installation.context,
                    metadataStore: installation.metadataStore,
                    installedRecords: contexts.installedExtensions,
                    volatileRecords: makeVolatileRecordReconciler(
                        installation: installation,
                        contexts: contexts
                    ),
                    packageMaintenance: makePackageMaintenance(
                        installation: installation
                    ),
                    runtimeAccess: controller.runtimeAccess,
                    enabledRuntimeActivation: activation.enabled,
                    runtimeRecovery: activation.recovery,
                    runtimeRetirement: retirement.runtime,
                    mutationRegistry: contexts.runtimeMutationRegistry,
                    loadRegistry: contexts.contextLoadRegistry,
                    shutDownRuntime: { [runtimeTermination = termination.termination] reason in
                        let result = runtimeTermination.shutDown(
                            reason: reason,
                            admission: .ifNoScopedMutations
                        )
                        if result.completed {
                            _ = runtimeTermination.executeRebuildPlan(
                                result.tabRebuildPlan,
                                reason: reason
                            )
                        }
                        return result
                    },
                    removeStoredData: {
                        [storageCleanup = termination.storageCleanup]
                        extensionID, mode in
                        await storageCleanup.removeStoredData(
                            for: extensionID,
                            mode: mode
                        )
                    },
                    removeGlobalInstallLedger: {
                        bootstrapChromeAdmission.removeFromLedger(
                            extensionIdentity: $0
                        )
                    }
            )
        )
    }

    static func assembleRuntimeInstallerPhase(
        installation: ExtensionInstallationGraphFoundation,
        runtime: ExtensionRuntimeAuthorityFoundation,
        contexts: ExtensionContextGraphFoundation,
        actions: ExtensionActionGraphFoundation,
        retirement: ExtensionRuntimeRetirementAssemblyProduct,
        coordination: ExtensionRuntimeCoordinationPhaseProduct,
        activation: ExtensionRuntimeActivationPhaseProduct,
        termination: ExtensionRuntimeTerminationPhaseProduct
    ) -> ExtensionInstallationService {
        let recordTransaction = ExtensionInstallationRecordTransaction(
            persistence: installation.metadataStore,
            installedRecords: contexts.installedExtensions
        )
        let runtimeReplacement = ExtensionInstallationRuntimeReplacement(
            retirement: retirement.runtime,
            recovery: activation.recovery
        )
        let storageCleanup = termination.storageCleanup
        let installer = ExtensionInstallationService(
                metadataStore: installation.metadataStore,
                recordTransaction: recordTransaction,
                runtimeActivation: activation.installation,
                runtimeReplacement: runtimeReplacement,
                failureSettlement: ExtensionInstallationFailureSettlement(
                    recordTransaction: recordTransaction,
                    runtimeReplacement: runtimeReplacement
                ),
                mutationRegistry: contexts.runtimeMutationRegistry,
                loadRegistry: contexts.contextLoadRegistry,
                sourceAdmission: ExtensionInstallationAdmission(),
                activePackageGenerations: installation.activePackageGenerations,
                packageMaintenance: makePackageMaintenance(
                    installation: installation
                ),
                packageFileExecutor: ExtensionPackageFileExecutor(),
                requestRuntimeForInstallation: {
                    [demand = coordination.demandCoordinator] in
                    _ = demand.requestRuntimeExplicitly(reason: .install)
                },
                removeStoredData: { extensionID, mode in
                    await storageCleanup.removeStoredData(
                        for: extensionID,
                        mode: mode
                    )
                },
                hasStoredDataCandidate: {
                    storageCleanup.hasStoredDataCandidate(for: $0)
                },
                traceStoreLifecycle: { phase, extensionID, manifest in
                    storageCleanup.traceLifecycle(
                        phase: phase,
                        extensionId: extensionID,
                        manifest: manifest
                    )
                },
                ensureStorageDirectory: { extensionID in
                    _ = storageCleanup.ensureStorageDirectoryExists(
                        for: extensionID
                    )
                },
                emitTrace: { [diagnostics = runtime.diagnostics] message in
                    guard ExtensionManager.isWebKitRuntimeTraceEnabled else {
                        return
                    }
                    diagnostics.trace(message)
                }
        )
        #if DEBUG
            installer.installDebugBeforePersist {
                [debug = actions.debugSignals] in
                debug.beforePersistInstalledRecord
            }
        #endif
        return installer
    }

    static func assembleRuntimeServicePhase(
        browserSupport: ExtensionRuntimeBrowserSupportPhaseProduct,
        catalog: InstalledExtensionCatalog,
        lifecycle: InstalledExtensionLifecycleService,
        installer: ExtensionInstallationService
    ) -> ExtensionRuntimeServicePhaseProduct {
        ExtensionRuntimeServicePhaseProduct(
            webViewConfiguration: browserSupport.webViewConfiguration,
            catalog: catalog,
            lifecycle: lifecycle,
            installer: installer,
            publicationEvidence: browserSupport.publicationEvidence,
            websiteDataQuiescence: browserSupport.websiteDataQuiescence,
            nativeMessagingSessions: browserSupport.nativeMessagingSessions
        )
    }

    private static func makeVolatileRecordReconciler(
        installation: ExtensionInstallationGraphFoundation,
        contexts: ExtensionContextGraphFoundation
    ) -> ExtensionVolatileInstallationRecordReconciler {
        ExtensionVolatileInstallationRecordReconciler(
            persistence: installation.metadataStore,
            installedRecords: contexts.installedExtensions
        )
    }

    private static func makePackageMaintenance(
        installation: ExtensionInstallationGraphFoundation
    ) -> ExtensionPackageMaintenance {
        ExtensionPackageMaintenance(
            layout: ExtensionPackageLayout(
                extensionsRoot: ExtensionPathSafety.extensionsDirectory()
            ),
            activeGenerations: installation.activePackageGenerations
        )
    }
}
