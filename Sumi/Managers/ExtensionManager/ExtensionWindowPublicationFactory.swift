import Foundation

/// Construction-only result split by semantic ownership. It is consumed
/// immediately by the attached-runtime factories and is never retained by a
/// product consumer.
@available(macOS 15.5, *)
@MainActor
struct ExtensionWindowPublicationAssembly {
    struct TabPublication {
        let gate: ExtensionRuntimePublicationGate
        let preparedVisibility: ExtensionPreparedTabVisibility
        let preparedTabs: ExtensionPreparedNormalTabQuery
        let publishedTabs: ExtensionPublishedNormalTabQuery
        let admission: ExtensionTabPublicationAdmission
    }

    struct WindowPublication {
        let normal: ExtensionNormalWindowLifecycle
        let auxiliary: ExtensionAuxiliaryWindowLifecycle
        let query: ExtensionWindowPublicationQuery
    }

    let tabs: TabPublication
    let windows: WindowPublication
    let adapters: ExtensionAdapterCatalog
    let profileIDForWindow: @MainActor (BrowserWindowState) -> UUID?
}

/// Builds the window/tab publication boundary from exact detached authorities
/// and one browser bridge. It owns no attachment state and cannot publish the
/// result by itself.
@available(macOS 15.5, *)
@MainActor
final class ExtensionWindowPublicationFactory {
    private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
    private let profileRuntime: ExtensionProfileRuntime
    private let contextPublications: ExtensionContextPublicationQuery
    private let tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority
    private let adapterStore: ExtensionBrowserAdapterStore
    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer
    private let profileTransition: ExtensionProfileRuntimeTransition
    private let profileWarmup: ExtensionProfileRuntimeWarmup
    #if DEBUG
        private var debugSignals: ExtensionManagerDebugSignals?
    #endif

    init(
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        profileRuntime: ExtensionProfileRuntime,
        contextPublications: ExtensionContextPublicationQuery,
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        adapterStore: ExtensionBrowserAdapterStore,
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        profileTransition: ExtensionProfileRuntimeTransition,
        profileWarmup: ExtensionProfileRuntimeWarmup
    ) {
        self.runtimeLoadStatus = runtimeLoadStatus
        self.profileRuntime = profileRuntime
        self.contextPublications = contextPublications
        self.tabPublicationRevisions = tabPublicationRevisions
        self.adapterStore = adapterStore
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.profileTransition = profileTransition
        self.profileWarmup = profileWarmup
    }

    #if DEBUG
        func installDebugSignals(_ signals: ExtensionManagerDebugSignals) {
            debugSignals = signals
        }
    #endif

    func assemble(
        bridge: BrowserExtensionBridgeComposition,
        controller: ExtensionControllerRuntimeComposition
    ) -> ExtensionWindowPublicationAssembly {
        #if DEBUG
            guard let debugSignals else {
                preconditionFailure("Debug signals must be installed before assembly")
            }
        #endif
        let gate = ExtensionRuntimePublicationGate()
        let preparedVisibility = ExtensionPreparedTabVisibility(gate: gate)
        let preparedTabs = ExtensionPreparedNormalTabQuery(
            tabPublicationRevisions: tabPublicationRevisions,
            tabs: bridge.tabs
        )
        let profileIDForWindow: @MainActor (BrowserWindowState) -> UUID? = {
            window in
            if window.isIncognito, let profile = window.ephemeralProfile {
                return profile.id
            }
            return window.currentProfileId
                ?? bridge.profiles.currentProfile()?.id
        }

        let normalLedger = ExtensionNormalWindowPublicationLedger()
        let normalValidator = ExtensionNormalWindowPublicationValidator(
            windowQuery: bridge.windows,
            tabQuery: bridge.tabs,
            runtimeLoadStatus: runtimeLoadStatus,
            profileRuntime: profileRuntime,
            profiles: controller.profiles,
            windowProfileID: profileIDForWindow,
            preparedTabs: preparedTabs,
            controllers: controller.controllers,
            adapterStore: adapterStore,
            runtimePublicationEvidence: runtimePublicationEvidence
        )
        let normalQuery = ExtensionNormalWindowPublicationQuery(
            ledger: normalLedger,
            validator: normalValidator
        )
        let auxiliaryLedger = ExtensionAuxiliaryWindowPublicationLedger()
        let auxiliaryQuery = ExtensionAuxiliaryWindowPublicationQuery(
            ledger: auxiliaryLedger,
            adapterStore: adapterStore,
            profileRuntime: profileRuntime,
            tabProfiles: controller.profiles
        )
        let windowQuery = ExtensionWindowPublicationQuery(
            normalWindows: normalQuery,
            auxiliaryWindows: auxiliaryQuery,
            control: bridge.auxiliaryWindows
        )
        let publishedTabs = ExtensionPublishedNormalTabQuery(
            prepared: preparedTabs,
            tabPublicationRevisions: tabPublicationRevisions,
            publicationGate: gate,
            profiles: controller.profiles,
            adapters: adapterStore,
            windows: windowQuery
        )
        let tabAdapters = ExtensionTabAdapterCatalog(
            adapterStore: adapterStore,
            evidence: ExtensionTabAdapterEvidenceFactory(
                tabQuery: bridge.tabs,
                tabPublicationRevisions: tabPublicationRevisions,
                profileIDForTab: controller.profiles.profileID,
                adapterStore: adapterStore,
                windowPublications: windowQuery,
                contextPublications: contextPublications
            ),
            projection: ExtensionTabAdapterProjectionFactory(
                windowQuery: bridge.windows,
                tabQuery: bridge.tabs,
                webViews: controller.tabWebViewResolver,
                auxiliaryWindows: bridge.auxiliaryWindows,
                windowPublications: windowQuery
            ),
            commands: ExtensionTabAdapterCommandFactory(
                windowQuery: bridge.windows,
                tabMutation: bridge.tabMutation,
                webViewHosting: bridge.webViews,
                auxiliaryWindows: bridge.auxiliaryWindows
            )
        )
        let windowIdentity = ExtensionWindowAdapterIdentityProjection(
            contextPublications: contextPublications,
            profileIDForWindow: profileIDForWindow,
            profileIDForTab: controller.profiles.profileID,
            extensionIDForContext: profileRuntime.extensionId
        )
        let adapters = ExtensionAdapterCatalog(
            miniWindows: ExtensionMiniWindowAdapterCatalog(
                adapterStore: adapterStore,
                auxiliaryWindows: bridge.auxiliaryWindows,
                windowPublications: windowQuery
            ),
            windows: ExtensionWindowAdapterCatalog(
                adapterStore: adapterStore,
                factory: ExtensionWindowAdapterFactory(
                    windowQuery: bridge.windows,
                    windowActivation: bridge.windowActivation,
                    identity: windowIdentity,
                    windowPublications: windowQuery,
                    tabAdapters: tabAdapters,
                    publishedTabs: publishedTabs,
                    preparedTabs: preparedTabs
                )
            ),
            tabs: tabAdapters
        )
        let normalResolver = ExtensionNormalWindowProjectionResolver(
            selection: ExtensionNormalWindowSelectionResolver(
                windows: bridge.windows,
                tabProfiles: controller.profiles,
                windowProfileID: profileIDForWindow,
                preparedTabs: preparedTabs
            ),
            publication: ExtensionNormalWindowPublicationProjectionResolver(
                runtimeLoadStatus: runtimeLoadStatus,
                profileRuntime: profileRuntime,
                controllers: controller.controllers,
                adapters: adapters,
                runtimePublicationEvidence: runtimePublicationEvidence,
                preparedTabVisibility: preparedVisibility
            ),
            profileSwitcher: ExtensionNormalWindowProfileSwitcher(
                profiles: bridge.profiles,
                transition: profileTransition,
                warmup: profileWarmup
            )
        )
        #if DEBUG
            let normal = ExtensionNormalWindowLifecycle(
                resolver: normalResolver,
                validator: normalValidator,
                ledger: normalLedger,
                adapterStore: adapterStore,
                preparedTabVisibility: preparedVisibility,
                debugEvent: { [debugSignals] event in
                    switch event {
                    case .didOpenWindow(let windowID):
                        debugSignals.hooks.didOpenNormalWindow?(windowID)
                    case .didFocusWindow(let windowID):
                        debugSignals.hooks.didFocusWindow?(windowID)
                    }
                }
            )
        #else
            let normal = ExtensionNormalWindowLifecycle(
                resolver: normalResolver,
                validator: normalValidator,
                ledger: normalLedger,
                adapterStore: adapterStore,
                preparedTabVisibility: preparedVisibility
            )
        #endif

        let auxiliaryExtensionsLoaded: @MainActor () -> Bool = {
            [runtimeLoadStatus] in runtimeLoadStatus.extensionsLoaded
        }
        let auxiliaryTabPublication = ExtensionAuxiliaryTabPublicationPreparer(
            runtimePublicationEvidence: runtimePublicationEvidence,
            adapterStore: adapterStore,
            adapterResolution: adapters,
            admission: ExtensionAuxiliaryTabPublicationAdmission(
                profileRuntime: profileRuntime,
                browserProfiles: bridge.profiles,
                tabProfiles: controller.profiles,
                controllers: controller.controllers,
                webViews: controller.webViews,
                controllerAdmission: controller.admission,
                extensionsLoaded: auxiliaryExtensionsLoaded
            ),
            receipts: ExtensionAuxiliaryTabPublicationReceiptFactory(
                runtimePublicationEvidence: runtimePublicationEvidence,
                profileRuntime: profileRuntime,
                browserProfiles: bridge.profiles,
                tabProfiles: controller.profiles,
                adapterStore: adapterStore,
                controllers: controller.controllers,
                webViews: controller.webViews,
                extensionsLoaded: auxiliaryExtensionsLoaded
            )
        )
        #if DEBUG
            let auxiliary = ExtensionAuxiliaryWindowLifecycle(
                ledger: auxiliaryLedger,
                publications: auxiliaryQuery,
                adapterStore: adapterStore,
                profileRuntime: profileRuntime,
                tabProfiles: controller.profiles,
                windowProfileID: profileIDForWindow,
                tabPublication: auxiliaryTabPublication,
                normalWindows: normal,
                debugEvent: { [debugSignals] event in
                    debugSignals.dispatchAuxiliaryPublication(event)
                }
            )
        #else
            let auxiliary = ExtensionAuxiliaryWindowLifecycle(
                ledger: auxiliaryLedger,
                publications: auxiliaryQuery,
                adapterStore: adapterStore,
                profileRuntime: profileRuntime,
                tabProfiles: controller.profiles,
                windowProfileID: profileIDForWindow,
                tabPublication: auxiliaryTabPublication,
                normalWindows: normal
            )
        #endif
        let admission = ExtensionTabPublicationAdmission(
            normalWindows: normal,
            publications: windowQuery,
            gate: gate
        )
        return ExtensionWindowPublicationAssembly(
            tabs: .init(
                gate: gate,
                preparedVisibility: preparedVisibility,
                preparedTabs: preparedTabs,
                publishedTabs: publishedTabs,
                admission: admission
            ),
            windows: .init(
                normal: normal,
                auxiliary: auxiliary,
                query: windowQuery
            ),
            adapters: adapters,
            profileIDForWindow: profileIDForWindow
        )
    }
}
