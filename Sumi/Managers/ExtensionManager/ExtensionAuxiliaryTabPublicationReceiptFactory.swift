import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
final class ExtensionAuxiliaryTabPublicationReceiptFactory {
    private let runtimePublicationEvidence: ExtensionRuntimePublicationEvidenceIssuer
    private let profileRuntime: ExtensionProfileRuntime
    private let browserProfiles: ExtensionBrowserProfileQuery
    private let tabProfiles: any ExtensionTabProfileResolving
    private let adapterStore: ExtensionBrowserAdapterStore
    private let controllers: any ExtensionTabControllerQuery
    private let webViews: ExtensionExactTabWebViewQuery
    private let extensionsLoaded: @MainActor () -> Bool

    init(
        runtimePublicationEvidence: ExtensionRuntimePublicationEvidenceIssuer,
        profileRuntime: ExtensionProfileRuntime,
        browserProfiles: ExtensionBrowserProfileQuery,
        tabProfiles: any ExtensionTabProfileResolving,
        adapterStore: ExtensionBrowserAdapterStore,
        controllers: any ExtensionTabControllerQuery,
        webViews: ExtensionExactTabWebViewQuery,
        extensionsLoaded: @escaping @MainActor () -> Bool
    ) {
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.profileRuntime = profileRuntime
        self.browserProfiles = browserProfiles
        self.tabProfiles = tabProfiles
        self.adapterStore = adapterStore
        self.controllers = controllers
        self.webViews = webViews
        self.extensionsLoaded = extensionsLoaded
    }

    func make(
        tab: Tab,
        webView: WKWebView,
        dataStore: WKWebsiteDataStore,
        profileID: UUID,
        ownerExtensionID: String,
        ownerContext: WKWebExtensionContext,
        controller: WKWebExtensionController,
        adapter: ExtensionTabAdapter,
        runtimePublication: ExtensionRuntimePublicationEvidence,
        contextBindingGeneration: UInt64,
        createdAdapter: Bool,
        stateToken: TabExtensionPrepublicationToken
    ) -> ExtensionAuxiliaryTabPublicationReceipt {
        ExtensionAuxiliaryTabPublicationReceipt(
            runtimePublicationEvidence: runtimePublicationEvidence,
            profileRuntime: profileRuntime,
            browserProfiles: browserProfiles,
            tabProfiles: tabProfiles,
            adapterStore: adapterStore,
            controllers: controllers,
            webViews: webViews,
            extensionsLoaded: extensionsLoaded,
            tab: tab,
            webView: webView,
            dataStore: dataStore,
            profileID: profileID,
            ownerExtensionID: ownerExtensionID,
            ownerContext: ownerContext,
            controller: controller,
            adapter: adapter,
            runtimePublication: runtimePublication,
            contextBindingGeneration: contextBindingGeneration,
            createdAdapter: createdAdapter,
            stateToken: stateToken
        )
    }
}
