import Foundation

/// Owns only revision, publication, profile, and adapter authorities.
@available(macOS 15.5, *)
@MainActor
final class ExtensionNormalTabRuntimeAuthorityFactory {
    private let tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority
    private let extensionLoadRevisions: ExtensionLoadRevisionAuthority
    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer
    private let runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority
    private let profileRuntime: ExtensionProfileRuntime
    private let adapterStore: ExtensionBrowserAdapterStore

    init(
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        extensionLoadRevisions: ExtensionLoadRevisionAuthority,
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore
    ) {
        self.tabPublicationRevisions = tabPublicationRevisions
        self.extensionLoadRevisions = extensionLoadRevisions
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.runtimeLoadStatus = runtimeLoadStatus
        self.profileRuntime = profileRuntime
        self.adapterStore = adapterStore
    }

    func assemble(
        bridge: BrowserExtensionBridgeComposition,
        controller: ExtensionControllerRuntimeComposition,
        publication: ExtensionWindowPublicationAssembly,
        preparation: ExtensionNormalTabRuntimePreparationAssembly
    ) -> ExtensionAttachedNormalTabRuntime {
        let runtime = ExtensionNormalTabRuntimeAssembler.assemble(
            tabs: bridge.tabs,
            liveWebViews: bridge.webViews,
            controllerRuntime: controller,
            gate: publication.tabs.gate,
            preparedTabVisibility: publication.tabs.preparedVisibility,
            preparedTabs: publication.tabs.preparedTabs,
            publishedTabs: publication.tabs.publishedTabs,
            admission: publication.tabs.admission,
            publications: publication.windows.query,
            tabPublicationRevisions: tabPublicationRevisions,
            extensionLoadRevisions: extensionLoadRevisions,
            runtimePublicationEvidence: runtimePublicationEvidence,
            runtimeLoadStatus: runtimeLoadStatus,
            profileRuntime: profileRuntime,
            adapterStore: adapterStore,
            adapterCatalog: publication.adapters,
            contextLoading: preparation.contextLoading,
            configurationPreparation: preparation.configuration,
            diagnostics: preparation.diagnostics
        )
        #if DEBUG
            let debugSignals = preparation.debugSignals
            runtime.tabLifecycleEvents.installDebugCallbacks(
                didOpen: { [debugSignals] in
                    debugSignals.hooks.didOpenTab?($0)
                },
                didClose: { [debugSignals] in
                    debugSignals.hooks.didCloseTab?($0)
                }
            )
            runtime.tabOpening.installDebugDidDeferOpen {
                [debugSignals] in
                debugSignals.hooks.didDeferOpenTab?($0, $1)
            }
            runtime.tabProperties.installDebugDidPublish {
                [debugSignals] in
                debugSignals.hooks.didChangeTabProperties?($0, $1)
            }
        #endif
        return runtime
    }
}
