import Foundation

/// Construction-only requested-tab transaction cluster. Controller callback
/// and auxiliary UI roles are composed by a separate surface factory.
@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabCoreAssembly {
    let targetResolver: ExtensionRequestedTabTargetResolver
    let createdTabRegistrar: ExtensionCreatedTabRuntimeRegistrar
    let initialTabPreparer: ExtensionInitialTabPublicationPreparer
    let contextPreloader: ExtensionRequestedTabContextPreloader
    let opening: ExtensionRequestedTabOpeningService
    let windowRouter: ExtensionWindowRequestRouter
}

@available(macOS 15.5, *)
@MainActor
final class ExtensionRequestedTabCoreFactory {
    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer
    private let profileRuntime: ExtensionProfileRuntime
    private let adapterStore: ExtensionBrowserAdapterStore
    private let deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore
    private let loadResolver: ExtensionRequestedTabLoadResolver
    private let recentRequests: ExtensionRecentTabRequestHistory
    private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore,
        loadResolver: ExtensionRequestedTabLoadResolver,
        recentRequests: ExtensionRecentTabRequestHistory,
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.profileRuntime = profileRuntime
        self.adapterStore = adapterStore
        self.deferredRuntimeOwners = deferredRuntimeOwners
        self.loadResolver = loadResolver
        self.recentRequests = recentRequests
        self.runtimeLoadStatus = runtimeLoadStatus
        self.diagnostics = diagnostics
    }

    func assemble(
        bridge: BrowserExtensionBridgeComposition,
        controller: ExtensionControllerRuntimeComposition,
        windows: ExtensionWindowPublicationAssembly,
        normalTabs: ExtensionAttachedNormalTabRuntime,
        windowCreation: any ExtensionRequestedWindowCreating
    ) -> ExtensionRequestedTabCoreAssembly {
        let contextLoading =
            deferredRuntimeOwners.initialDocumentRuntimePreparationOwner
        let targetResolver = ExtensionRequestedTabTargetResolver(
            browserContext: { bridge.requestedTabTargets },
            profileRuntime: profileRuntime,
            tabProfiles: controller.profiles,
            currentProfileID: { bridge.profiles.currentProfile()?.id },
            windowProfileID: windows.profileIDForWindow,
            publications: windows.windows.query
        )
        let createdTabRegistrar = ExtensionCreatedTabRuntimeRegistrar(
            runtimePublicationEvidence: runtimePublicationEvidence,
            profileRuntime: profileRuntime,
            tabProfiles: controller.profiles,
            browserProfiles: bridge.profiles,
            adapterStore: adapterStore,
            controllers: controller.controllers,
            webViews: controller.webViews,
            controllerAdmission: controller.admission,
            adapterResolution: windows.adapters,
            contextLoading: contextLoading,
            publications: windows.windows.query,
            publicationAdmission: windows.tabs.admission,
            events: normalTabs.tabLifecycleEvents,
            extensionsLoaded: { [runtimeLoadStatus] in
                runtimeLoadStatus.extensionsLoaded
            },
            diagnostics: diagnostics
        )
        let initialTabAdapters = ExtensionCreatedTabAdapterPublication(
            store: adapterStore,
            resolution: windows.adapters
        )
        let initialExtensionsLoaded: @MainActor () -> Bool = {
            [runtimeLoadStatus] in runtimeLoadStatus.extensionsLoaded
        }
        let initialTabPreparer = ExtensionInitialTabPublicationPreparer(
            runtimePublicationEvidence: runtimePublicationEvidence,
            profileRuntime: profileRuntime,
            residenceAdmission: ExtensionInitialTabResidenceAdmission(
                browserProfiles: bridge.profiles,
                tabProfiles: controller.profiles,
                windowProfileID: windows.profileIDForWindow,
                webViews: controller.webViews,
                residences: bridge.tabResidences
            ),
            runtimeAdmission: ExtensionInitialTabRuntimeAdmission(
                profileRuntime: profileRuntime,
                contextLoading: contextLoading,
                controllerQuery: controller.controllers,
                controllerAdmission: controller.admission,
                extensionsLoaded: initialExtensionsLoaded
            ),
            adapters: initialTabAdapters,
            validator: ExtensionInitialTabPublicationValidator(
                runtimePublicationEvidence: runtimePublicationEvidence,
                profileRuntime: profileRuntime,
                controllerQuery: controller.controllers,
                webViews: controller.webViews,
                contextLoading: contextLoading,
                windowRegistry: bridge.windows,
                windowPublications: windows.windows.query,
                adapters: initialTabAdapters,
                residences: bridge.tabResidences,
                extensionsLoaded: initialExtensionsLoaded
            ),
            retirement: ExtensionInitialTabPublicationRetirement(
                events: normalTabs.tabLifecycleEvents,
                adapters: initialTabAdapters
            ),
            diagnostics: diagnostics
        )
        let contextPreloader = ExtensionRequestedTabContextPreloader(
            loadResolver: loadResolver,
            placement: targetResolver,
            profileRuntime: profileRuntime,
            windowProfileID: windows.profileIDForWindow,
            currentProfileID: { bridge.profiles.currentProfile()?.id },
            contextLoading: contextLoading
        )
        let opening = ExtensionRequestedTabOpeningService(
            recentRequests: recentRequests,
            loadResolver: loadResolver,
            placement: targetResolver,
            materializer: normalTabs.requestedTabWebViewMaterializer,
            registrar: createdTabRegistrar,
            browserContext: { bridge.tabMutation },
            profileRuntime: profileRuntime,
            tabProfileID: { [profiles = controller.profiles] tab in
                profiles.profileID(for: tab)
            },
            windowProfileID: windows.profileIDForWindow,
            hasTabAdapter: { [adapters = windows.adapters] tab in
                adapters.stableAdapter(for: tab) != nil
            }
        )
        let windowRouter = ExtensionWindowRequestRouter(
            profileRuntime: profileRuntime,
            targetResolver: targetResolver,
            loadResolver: loadResolver,
            contextPreloader: contextPreloader,
            tabOpening: opening,
            windowQuery: {
                bridge.availability.isAvailable ? bridge.windows : nil
            },
            windowCreation: { windowCreation },
            publishedWindow: { [publications = windows.windows.query]
                window,
                profileID in
                publications.publishedWindowAdapter(
                    for: window,
                    profileID: profileID
                )
            }
        )
        return ExtensionRequestedTabCoreAssembly(
            targetResolver: targetResolver,
            createdTabRegistrar: createdTabRegistrar,
            initialTabPreparer: initialTabPreparer,
            contextPreloader: contextPreloader,
            opening: opening,
            windowRouter: windowRouter
        )
    }
}
