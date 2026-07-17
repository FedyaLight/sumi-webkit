import Foundation

/// Stateless final assembly stage. It distributes exact roles to concrete
/// consumers, then seals the private subsystem nodes behind lifetime owners.
@available(macOS 15.5, *)
@MainActor
enum ExtensionManagerGraphFinalizer {
    static func finalize(
        _ f: ExtensionManagerAssemblyFoundation,
        assembled: ExtensionManagerAssemblyResult
    ) -> ExtensionManagerRootGraphs {
        let windowPublications = ExtensionWindowPublicationFactory(
            runtimeLoadStatus: f.runtime.loadStatus,
            profileRuntime: f.runtime.profileRuntime,
            contextPublications: assembled.contexts.contextPublications,
            tabPublicationRevisions: f.runtime.tabPublicationRevisions,
            adapterStore: f.actions.adapterStore,
            runtimePublicationEvidence:
                assembled.normalTabs.publicationEvidence,
            profileTransition: assembled.contexts.profileTransition
        )
        let normalTabRuntime = ExtensionAttachedNormalTabRuntimeFactory(
            tabPublicationRevisions: f.runtime.tabPublicationRevisions,
            extensionLoadRevisions: f.runtime.loadRevisions,
            runtimePublicationEvidence:
                assembled.normalTabs.publicationEvidence,
            runtimeLoadStatus: f.runtime.loadStatus,
            profileRuntime: f.runtime.profileRuntime,
            adapterStore: f.actions.adapterStore,
            deferredRuntimeOwners: assembled.normalTabs.deferredRuntimeOwners,
            configurationPreparation:
                assembled.normalTabs.configurationPreparation,
            diagnostics: f.runtime.diagnostics
        )
        let publicationTransactions = ExtensionPublicationTransactionFactory(
            tabPublicationRevisions: f.runtime.tabPublicationRevisions,
            runtimePublicationEvidence:
                assembled.normalTabs.publicationEvidence,
            runtimeLoadStatus: f.runtime.loadStatus,
            profileRuntime: f.runtime.profileRuntime,
            adapterStore: f.actions.adapterStore,
            diagnostics: f.runtime.diagnostics,
            reloadSettlement: f.browser.reloads
        )
        #if DEBUG
            windowPublications.installDebugSignals(f.actions.debugSignals)
            normalTabRuntime.installDebugSignals(f.actions.debugSignals)
            publicationTransactions.installDebugSignals(
                f.actions.debugSignals
            )
        #endif
        let runtimeAssembler = ExtensionAttachedBrowserRuntimeAssembler(
            controllers: ExtensionAttachedControllerRuntimeFactory(
                runtimeLoadStatus: f.runtime.loadStatus,
                profileRuntime: f.runtime.profileRuntime,
                contexts: assembled.contexts.contextPublications,
                preludeInstaller: assembled.controller.permissionPreludes,
                diagnostics: f.runtime.diagnostics
            ),
            windows: windowPublications,
            normalTabs: normalTabRuntime,
            publicationTransactions: publicationTransactions,
            requestedTabCore: ExtensionRequestedTabCoreFactory(
                runtimePublicationEvidence:
                    assembled.normalTabs.publicationEvidence,
                profileRuntime: f.runtime.profileRuntime,
                adapterStore: f.actions.adapterStore,
                deferredRuntimeOwners:
                    assembled.normalTabs.deferredRuntimeOwners,
                loadResolver: f.contexts.requestedTabLoadResolver,
                recentRequests: f.contexts.recentTabRequests,
                runtimeLoadStatus: f.runtime.loadStatus,
                diagnostics: f.runtime.diagnostics
            ),
            requestedTabSurfaces: ExtensionRequestedTabBrowserSurfaceFactory(
                profileRuntime: f.runtime.profileRuntime,
                installedExtensions: f.contexts.installedExtensions,
                controllerProvisioning: assembled.controller.provisioning,
                configurationPreparation:
                    assembled.normalTabs.configurationPreparation,
                callbackAdmission: assembled.controller.callbackAdmission,
                browserConfiguration: f.controller.browserConfiguration,
                deferredRuntimeOwners:
                    assembled.normalTabs.deferredRuntimeOwners,
                loadResolver: f.contexts.requestedTabLoadResolver,
                recentRequests: f.contexts.recentTabRequests
            )
        )
        let runtimeAttacher = ExtensionBrowserRuntimeAttacher(
            attachment: f.browser.attachment,
            runtimeAssembler: runtimeAssembler,
            routeInstaller: ExtensionControllerBrowserRouteInstaller(
                delegateBridge: assembled.controller.delegateBridge,
                actionSurfaces: assembled.actions.surface.publisher,
                popupAdmission:
                    assembled.actions.presentation.popupCallbackAdmission,
                popupInvocations: f.actions.actionPopupInvocations,
                popupCoordinator:
                    assembled.actions.presentation.popupCoordinator,
                optionsWindows: f.actions.optionsWindows
            ),
            profiles: ExtensionBrowserAttachmentProfileCoordinator(
                profileRuntime: f.runtime.profileRuntime,
                profileTransition: assembled.contexts.profileTransition,
                diagnostics: f.runtime.diagnostics,
                browserEvents: f.browser.events
            )
        )
        f.contexts.installedExtensions.connectRecordChanges {
            [weak toolbar = assembled.actions.surface.toolbarPinning] in
            toolbar?.reconcilePinnedToolbarExtensions()
        }
        assembled.actions.surface.toolbarPinning
            .reloadPinnedToolbarExtensionsForCurrentProfile()
        assembled.installation.catalog.load()

        let lifetimeControl = ExtensionManagerLifetimeControl(
            installedExtensions: f.contexts.installedExtensions,
            runtimeDemand: f.runtime.demand,
            mutations: f.contexts.runtimeMutationRegistry
        )
        let moduleRuntimeFactory = ExtensionModuleBrowserRuntimeFactory(
            configuration: assembled.normalTabs.configurationPreparation,
            lifecycle: assembled.normalTabs.lifecycle,
            requestedTabs: assembled.normalTabs.requestedTabs,
            browserEvents: f.browser.events,
            profileTransition: assembled.contexts.profileTransition,
            keyboard: assembled.actions.presentation.keyboardCommands,
            recentRequests: f.contexts.recentTabRequests,
            deferredRuntimeOwners: assembled.normalTabs.deferredRuntimeOwners,
            nativeMessaging: assembled.controller.nativeMessagingSessions
        )
        let surfaceBinding = makeSurfaceBinding(
            installedExtensions: f.contexts.installedExtensions,
            surfacePublication: f.actions.surfacePublication,
            siteAccess: assembled.actions.surface.siteAccess
        )
        let toolbarRuntime = ExtensionManagerToolbarRuntimeFactory.make(
            attachment: f.browser.attachment,
            profileRuntime: f.runtime.profileRuntime,
            contexts: assembled.contexts,
            controller: assembled.controller,
            actions: assembled.actions,
            normalTabs: assembled.normalTabs,
            actionAnchors: f.actions.actionAnchors,
            optionsWindows: f.actions.optionsWindows
        )
        let autofillRuntime = makeAutofillRuntime(
            surfacePublication: f.actions.surfacePublication,
            normalTabs: assembled.normalTabs.query
        )
        let compatibilityDiagnostics = makeCompatibilityDiagnostics(
            installedExtensions: f.contexts.installedExtensions,
            profileRuntime: f.runtime.profileRuntime,
            lifecycle: f.runtime.lifecycle,
            surfacePublication: f.actions.surfacePublication,
            normalTabs: assembled.normalTabs.query,
            nativeMessaging: assembled.controller.nativeMessagingSessions
        )
        let settingsCatalog = ExtensionSettingsCatalogBinding(
            installed: f.contexts.installedExtensions,
            lifecycle: assembled.installation.lifecycle,
            installer: assembled.installation.installer
        )

        #if DEBUG
            let contextGraph = ExtensionContextLifecycleGraph(
                runtimeLifetime: assembled.contexts.runtimeLifetime,
                transactionLifetime: assembled.contexts.transactionLifetime,
                publicationLifetime: assembled.contexts.publicationLifetime,
                control: lifetimeControl,
                websiteDataQuiescence:
                    assembled.contexts.websiteDataQuiescence,
                profileRetirement: ExtensionProfileRuntimeRetirement(
                    profileRuntime: f.runtime.profileRuntime,
                    websiteDataQuiescence:
                        assembled.contexts.websiteDataQuiescence,
                    controllerProvisioning: assembled.controller.provisioning
                ),
                testTaskDrain: ExtensionRuntimeTaskDrain(
                    deferredRuntimeOwners:
                        assembled.normalTabs.deferredRuntimeOwners,
                    normalTabLifecycle: assembled.normalTabs.lifecycle,
                    nativeMessaging:
                        assembled.controller.nativeMessagingSessions,
                    backgroundRuntimeState:
                        f.contexts.backgroundRuntimeState
                )
            )
            let actionGraph = ExtensionActionUIGraph(
                surfaceLifetime: assembled.actions.surfaceLifetime,
                policyLifetime: assembled.actions.policyLifetime,
                popupLifetime: assembled.actions.popupLifetime,
                presentationLifetime: assembled.actions.presentationLifetime,
                surfaceBinding: surfaceBinding,
                toolbarRuntime: toolbarRuntime,
                autofillRuntime: autofillRuntime,
                compatibilityDiagnostics: compatibilityDiagnostics,
                debugSignals: f.actions.debugSignals
            )
        #else
            let contextGraph = ExtensionContextLifecycleGraph(
                runtimeLifetime: assembled.contexts.runtimeLifetime,
                transactionLifetime: assembled.contexts.transactionLifetime,
                publicationLifetime: assembled.contexts.publicationLifetime,
                control: lifetimeControl,
                websiteDataQuiescence:
                    assembled.contexts.websiteDataQuiescence,
                profileRetirement: ExtensionProfileRuntimeRetirement(
                    profileRuntime: f.runtime.profileRuntime,
                    websiteDataQuiescence:
                        assembled.contexts.websiteDataQuiescence,
                    controllerProvisioning: assembled.controller.provisioning
                )
            )
            let actionGraph = ExtensionActionUIGraph(
                surfaceLifetime: assembled.actions.surfaceLifetime,
                policyLifetime: assembled.actions.policyLifetime,
                popupLifetime: assembled.actions.popupLifetime,
                presentationLifetime: assembled.actions.presentationLifetime,
                surfaceBinding: surfaceBinding,
                toolbarRuntime: toolbarRuntime,
                autofillRuntime: autofillRuntime,
                compatibilityDiagnostics: compatibilityDiagnostics
            )
        #endif

        return ExtensionManagerRootGraphs(
            controller: ExtensionControllerGraph(
                lifetime: assembled.controller.lifetime
            ),
            contexts: contextGraph,
            normalTabs: ExtensionNormalTabGraph(
                preparationLifetime: assembled.normalTabs.preparationLifetime,
                publicationLifetime: assembled.normalTabs.publicationLifetime,
                moduleRuntimeFactory: moduleRuntimeFactory
            ),
            runtimePublication: ExtensionRuntimePublicationGraphFactory.make(
                attachment: f.browser.attachment,
                browserEvents: f.browser.events,
                reloads: f.browser.reloads,
                attacher: runtimeAttacher
            ),
            actions: actionGraph,
            installation: ExtensionInstallationRetirementGraph(
                lifetime: assembled.installation.lifetime,
                settingsCatalog: settingsCatalog,
                runtimeTermination: assembled.installation.runtimeTermination
            )
        )
    }

    private static func makeSurfaceBinding(
        installedExtensions: InstalledExtensionCollection,
        surfacePublication: ExtensionManagerSurfacePublication,
        siteAccess: ExtensionSiteAccessPolicyCoordinator
    ) -> BrowserExtensionSurfaceBinding {
        BrowserExtensionSurfaceBinding(
            installedExtensionsPublisher:
                installedExtensions.$records,
            actionStatesPublisher:
                surfacePublication.actionStatesPublisher,
            actionPresentationChangePublisher:
                surfacePublication.actionPresentationChangePublisher,
            siteAccessPolicyChangePublisher:
                surfacePublication.siteAccessPolicyChangePublisher,
            installedExtensions: {
                [installedExtensions] in installedExtensions.records
            },
            siteAccessPolicySnapshot: {
                [siteAccess]
                extensionIDs, profileID in
                siteAccess.siteAccessPolicySnapshot(
                    extensionIds: extensionIDs,
                    profileId: profileID
                )
            }
        )
    }

    private static func makeAutofillRuntime(
        surfacePublication: ExtensionManagerSurfacePublication,
        normalTabs: ExtensionBrowserAttachmentAuthority.NormalTabQuery
    ) -> SafariExtensionAutofillRuntime {
        SafariExtensionAutofillRuntime(
            extensionsLoaded: {
                [surfacePublication] in surfacePublication.extensionsLoaded
            },
            targetSnapshot: { [normalTabs] tab, context in
                normalTabs.targetSnapshot(tab: tab, context: context)
            }
        )
    }

    private static func makeCompatibilityDiagnostics(
        installedExtensions: InstalledExtensionCollection,
        profileRuntime: ExtensionProfileRuntime,
        lifecycle: ExtensionRuntimeLifecycleAuthority,
        surfacePublication: ExtensionManagerSurfacePublication,
        normalTabs: ExtensionBrowserAttachmentAuthority.NormalTabQuery,
        nativeMessaging: ExtensionNativeMessagingSessionControl
    ) -> ExtensionCompatibilityDiagnosticsSnapshotProvider {
        ExtensionCompatibilityDiagnosticsSnapshotProvider {
            ExtensionCompatibilityDiagnosticsSnapshot(
                installedExtensions: installedExtensions.records,
                reportRuntime: SafariCompatibilityReportRuntime(
                    currentTab: { [normalTabs] in normalTabs.currentTab() },
                    stableAdapter: {
                        [normalTabs] in normalTabs.stableAdapter(for: $0)
                    },
                    context: { [profileRuntime] extensionID in
                        guard let profileID = profileRuntime.currentProfileId else {
                            return nil
                        }
                        return profileRuntime.contexts(for: profileID)[extensionID]
                    },
                    actionState: { [surfacePublication] in
                        surfacePublication.actionStatesByExtensionID[$0]
                    },
                    lifecycleState: { [lifecycle] in lifecycle.state }
                ),
                nativeMessagingAdapters:
                    nativeMessaging.diagnosticsAdapterRegistry()
            )
        }
    }
}
