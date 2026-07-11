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
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        controllerBinding: ExtensionControllerAttachmentOwner,
        adapterResolution: ExtensionAdapterResolutionOwner,
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
            runtimeSession: runtimeSession,
            profileRuntime: profileRuntime,
            controllerBinding: controllerBinding,
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
        runtime: ExtensionManagerRuntime,
        reason: String
    ) -> Bool {
        guard let base = validator.prepareBase(for: tab, runtime: runtime) else {
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
            createdAdapter: preparedAdapter.created,
            stateToken: preparation,
            reason: reason
        )
        guard validator.preparedEvidenceIsCurrent(
            evidence,
            runtime: runtime
        ) else {
            let restored = tab.extensionPageRuntimeOwner
                .rollbackWindowPrepublication(preparation)
            if restored {
                adapters.removeCreatedAdapter(preparedAdapter, for: tab)
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
        return receipt.commitOpen(runtime: runtime)
    }

    private func tabDescription(_ tab: Tab) -> String {
        "tab=\(tab.id.uuidString.prefix(8)) url=\(tab.url.absoluteString)"
    }
}
