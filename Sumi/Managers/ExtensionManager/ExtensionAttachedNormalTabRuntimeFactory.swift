import Foundation

/// Coordinates exact authority and preparation assemblies for one attached
/// normal-tab runtime.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAttachedNormalTabRuntimeFactory {
    private let authorities: ExtensionNormalTabRuntimeAuthorityFactory
    private let preparation: ExtensionNormalTabRuntimePreparationFactory

    init(
        tabPublicationRevisions: ExtensionTabPublicationRevisionAuthority,
        extensionLoadRevisions: ExtensionLoadRevisionAuthority,
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        runtimeLoadStatus: ExtensionRuntimeLoadStatusAuthority,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        deferredRuntimeOwners: ExtensionDeferredRuntimeOwnerStore,
        configurationPreparation: ExtensionWebViewConfigurationPreparation,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        authorities = ExtensionNormalTabRuntimeAuthorityFactory(
            tabPublicationRevisions: tabPublicationRevisions,
            extensionLoadRevisions: extensionLoadRevisions,
            runtimePublicationEvidence: runtimePublicationEvidence,
            runtimeLoadStatus: runtimeLoadStatus,
            profileRuntime: profileRuntime,
            adapterStore: adapterStore
        )
        preparation = ExtensionNormalTabRuntimePreparationFactory(
            deferredRuntimeOwners: deferredRuntimeOwners,
            configurationPreparation: configurationPreparation,
            diagnostics: diagnostics
        )
    }

    #if DEBUG
        func installDebugSignals(_ signals: ExtensionManagerDebugSignals) {
            preparation.installDebugSignals(signals)
        }
    #endif

    func assemble(
        bridge: BrowserExtensionBridgeComposition,
        controller: ExtensionControllerRuntimeComposition,
        publication: ExtensionWindowPublicationAssembly
    ) -> ExtensionAttachedNormalTabRuntime {
        authorities.assemble(
            bridge: bridge,
            controller: controller,
            publication: publication,
            preparation: preparation.makeAssembly()
        )
    }
}
