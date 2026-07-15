import Foundation

@available(macOS 15.5, *)
@MainActor
final class ExtensionCreatedTabRuntimeRegistrar {
    private let validator: ExtensionCreatedTabPublicationValidator
    private let publicationAdmission: ExtensionTabPublicationAdmission
    private let adapters: ExtensionCreatedTabAdapterPublication
    private let retirement: ExtensionCreatedTabPublicationRetirement
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        profileRuntime: ExtensionProfileRuntime,
        tabProfiles: any ExtensionTabProfileResolving,
        browserProfiles: ExtensionBrowserProfileQuery,
        adapterStore: ExtensionBrowserAdapterStore,
        controllers: any ExtensionTabControllerQuery,
        webViews: ExtensionExactTabWebViewQuery,
        controllerAdmission: any ExtensionWebViewControllerAdmitting,
        adapterResolution: ExtensionAdapterCatalog,
        contextLoading: any ExtensionContentScriptContextLoading,
        publications: ExtensionWindowPublicationQuery,
        publicationAdmission: ExtensionTabPublicationAdmission,
        events: any ExtensionTabLifecycleEventSink,
        extensionsLoaded: @escaping @MainActor () -> Bool,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        let adapters = ExtensionCreatedTabAdapterPublication(
            store: adapterStore,
            resolution: adapterResolution
        )
        self.adapters = adapters
        validator = ExtensionCreatedTabPublicationValidator(
            runtimePublicationEvidence: runtimePublicationEvidence,
            profileRuntime: profileRuntime,
            tabProfiles: tabProfiles,
            browserProfiles: browserProfiles,
            controllers: controllers,
            webViews: webViews,
            controllerAdmission: controllerAdmission,
            contextLoading: contextLoading,
            publications: publications,
            adapters: adapters,
            extensionsLoaded: extensionsLoaded
        )
        self.publicationAdmission = publicationAdmission
        retirement = ExtensionCreatedTabPublicationRetirement(
            events: events,
            adapters: adapters
        )
        self.diagnostics = diagnostics
    }

    @discardableResult
    func register(
        _ tab: Tab,
        reason: String
    ) -> Bool {
        guard let base = validator.prepareBase(for: tab) else {
            diagnostics.trace(
                "registerExtensionCreatedTab rejected reason=\(reason) because=runtimePreparationFailed \(tabDescription(tab))"
            )
            return false
        }

        let preparation = tab.extensionPageRuntimeOwner
            .prepareForWindowPrepublication(generation: base.generation)
        guard tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: base.generation) == false,
              publicationAdmission.prepareTabOpen(tab),
              let preparedAdapter = adapters.prepare(for: tab)
        else {
            let restored = tab.extensionPageRuntimeOwner
                .rollbackWindowPrepublication(preparation)
            diagnostics.trace(
                "registerExtensionCreatedTab rejected reason=\(reason) because=receiptPreparationFailed generation=\(base.generation) rollback=\(restored) \(tabDescription(tab))"
            )
            return false
        }

        let evidence = ExtensionCreatedTabPublicationEvidence(
            base: base,
            adapter: preparedAdapter.adapter,
            stateToken: preparation,
            reason: reason
        )
        guard validator.preparedEvidenceIsCurrent(evidence) else {
            let restored = tab.extensionPageRuntimeOwner
                .rollbackWindowPrepublication(preparation)
            if restored {
                adapters.retireExactAdapter(
                    preparedAdapter.adapter,
                    for: tab
                )
            }
            diagnostics.trace(
                "registerExtensionCreatedTab rejected reason=\(reason) because=receiptEvidenceStale generation=\(base.generation) rollback=\(restored) \(tabDescription(tab))"
            )
            return false
        }

        let receipt = ExtensionCreatedTabPublicationReceipt(
            validator: validator,
            retirement: retirement,
            diagnostics: diagnostics,
            evidence: evidence
        )
        return receipt.commitOpen()
    }

    private func tabDescription(_ tab: Tab) -> String {
        "tab=\(tab.id.uuidString.prefix(8)) url=\(tab.url.absoluteString)"
    }
}
