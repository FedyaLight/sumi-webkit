import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionAuxiliaryTabPublicationPreparing: AnyObject {
    func prepareTabPublication(
        for session: AuxiliaryWindowSession,
        profileID: UUID,
        ownerExtensionID: String,
        ownerContext: WKWebExtensionContext
    ) -> ExtensionAuxiliaryTabPublicationReceipt?
}

/// Silently prepares the exact owner-context Tab half of an auxiliary
/// Tab+Window publication. It emits no WebKit event; the window lifecycle
/// decides whether the returned receipt commits or rolls back.
@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryTabPublicationPreparer:
    ExtensionAuxiliaryTabPublicationPreparing {
    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer
    private let adapterStore: ExtensionBrowserAdapterStore
    private let adapterResolution: ExtensionAdapterCatalog
    private let admission: ExtensionAuxiliaryTabPublicationAdmission
    private let receipts: ExtensionAuxiliaryTabPublicationReceiptFactory

    init(
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        adapterStore: ExtensionBrowserAdapterStore,
        adapterResolution: ExtensionAdapterCatalog,
        admission: ExtensionAuxiliaryTabPublicationAdmission,
        receipts: ExtensionAuxiliaryTabPublicationReceiptFactory
    ) {
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.adapterStore = adapterStore
        self.adapterResolution = adapterResolution
        self.admission = admission
        self.receipts = receipts
    }

    func prepareTabPublication(
        for session: AuxiliaryWindowSession,
        profileID: UUID,
        ownerExtensionID: String,
        ownerContext: WKWebExtensionContext
    ) -> ExtensionAuxiliaryTabPublicationReceipt? {
        let tab = session.tab
        guard let admitted = admission.admit(
            session: session,
            profileID: profileID,
            ownerExtensionID: ownerExtensionID,
            ownerContext: ownerContext
        ) else { return nil }

        let runtimePublication = runtimePublicationEvidence.issue()
        let generation = runtimePublication.tabPublication
        let previousAdapter = adapterStore.tabAdapters[tab.id]
        let stateToken = tab.extensionPageRuntimeOwner
            .prepareForWindowPrepublication(generation: generation)

        guard tab.extensionPageRuntimeOwner
                .hasDidOpenTabNotification(for: generation) == false,
              let adapter = adapterResolution.stableAdapter(for: tab),
              adapterStore.tabAdapters[tab.id] === adapter
        else {
            _ = tab.extensionPageRuntimeOwner.rollbackWindowPrepublication(
                stateToken
            )
            removeNewAdapter(for: tab, previousAdapter: previousAdapter)
            return nil
        }

        return receipts.make(
            tab: tab,
            webView: session.webView,
            dataStore: admitted.dataStore,
            profileID: profileID,
            ownerExtensionID: ownerExtensionID,
            ownerContext: ownerContext,
            controller: admitted.controller,
            adapter: adapter,
            runtimePublication: runtimePublication,
            contextBindingGeneration: admitted.contextBindingGeneration,
            createdAdapter: previousAdapter == nil,
            stateToken: stateToken
        )
    }

    private func removeNewAdapter(
        for tab: Tab,
        previousAdapter: ExtensionTabAdapter?
    ) {
        guard previousAdapter == nil,
              let created = adapterStore.tabAdapters[tab.id]
        else {
            return
        }
        _ = adapterStore.removeTabAdapter(
            for: tab.id,
            ifIdenticalTo: created
        )
    }
}
