import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
protocol ExtensionAuxiliaryTabPublicationPreparing: AnyObject {
    func prepareTabPublication(
        for session: AuxiliaryWindowSession,
        profileID: UUID,
        ownerExtensionID: String,
        ownerContext: WKWebExtensionContext,
        runtime: ExtensionManagerRuntime
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
    private let profileRuntime: ExtensionProfileRuntime
    private let adapterStore: ExtensionBrowserAdapterStore
    private let controllers: any ExtensionTabControllerQuery
    private let webViews: ExtensionExactTabWebViewQuery
    private let controllerAdmission: any ExtensionWebViewControllerAdmitting
    private let adapterResolution: ExtensionAdapterCatalog
    private let extensionsLoaded: @MainActor () -> Bool

    init(
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        controllers: any ExtensionTabControllerQuery,
        webViews: ExtensionExactTabWebViewQuery,
        controllerAdmission: any ExtensionWebViewControllerAdmitting,
        adapterResolution: ExtensionAdapterCatalog,
        extensionsLoaded: @escaping @MainActor () -> Bool
    ) {
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.profileRuntime = profileRuntime
        self.adapterStore = adapterStore
        self.controllers = controllers
        self.webViews = webViews
        self.controllerAdmission = controllerAdmission
        self.adapterResolution = adapterResolution
        self.extensionsLoaded = extensionsLoaded
    }

    func prepareTabPublication(
        for session: AuxiliaryWindowSession,
        profileID: UUID,
        ownerExtensionID: String,
        ownerContext: WKWebExtensionContext,
        runtime: ExtensionManagerRuntime
    ) -> ExtensionAuxiliaryTabPublicationReceipt? {
        let tab = session.tab
        let webView = session.webView
        guard extensionsLoaded(),
              session.isPrivate == false,
              profileRuntime.resolvedProfileId(
                  for: tab,
                  runtime: runtime
              ) == profileID,
              let dataStore = runtime.profile(profileID)?.dataStore,
              webView.configuration.websiteDataStore === dataStore,
              profileRuntime.profileId(for: ownerContext) == profileID,
              profileRuntime.extensionId(for: ownerContext)
                == ownerExtensionID,
              profileRuntime.contexts(for: profileID)[ownerExtensionID]
                === ownerContext,
              webViews.untrackedWebView(for: tab)
                === webView,
              let controller = controllers.existingController(for: tab),
              controllerAdmission.admit(
                  controller,
                  profileID: profileID,
                  to: webView,
                  for: tab
              ).isUsable,
              profileRuntime.controller(for: profileID) === controller,
              webView.configuration.webExtensionController === controller
        else {
            return nil
        }

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

        return ExtensionAuxiliaryTabPublicationReceipt(
            runtimePublicationEvidence: runtimePublicationEvidence,
            profileRuntime: profileRuntime,
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
            contextBindingGeneration: profileRuntime
                .contextBindingGeneration(for: profileID),
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
