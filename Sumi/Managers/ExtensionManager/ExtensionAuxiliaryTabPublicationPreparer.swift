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
    private let runtimeSession: ExtensionRuntimeSession
    private let profileRuntime: ExtensionProfileRuntime
    private let adapterStore: ExtensionBrowserAdapterStore
    private let controllerBinding: ExtensionControllerAttachmentOwner
    private let adapterResolution: ExtensionAdapterCatalog
    private let extensionsLoaded: @MainActor () -> Bool

    init(
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        controllerBinding: ExtensionControllerAttachmentOwner,
        adapterResolution: ExtensionAdapterCatalog,
        extensionsLoaded: @escaping @MainActor () -> Bool
    ) {
        self.runtimeSession = runtimeSession
        self.profileRuntime = profileRuntime
        self.adapterStore = adapterStore
        self.controllerBinding = controllerBinding
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
              controllerBinding.ownedUntrackedCurrentWebView(for: tab)
                === webView,
              controllerBinding.attachExtensionControllerIfNeeded(
                  to: webView,
                  for: tab
              ),
              let controller = controllerBinding.extensionController(for: tab),
              profileRuntime.controller(for: profileID) === controller,
              webView.configuration.webExtensionController === controller
        else {
            return nil
        }

        let generation = runtimeSession.tabOpenNotificationGeneration
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
            runtimeSession: runtimeSession,
            profileRuntime: profileRuntime,
            adapterStore: adapterStore,
            controllerBinding: controllerBinding,
            extensionsLoaded: extensionsLoaded,
            tab: tab,
            webView: webView,
            dataStore: dataStore,
            profileID: profileID,
            ownerExtensionID: ownerExtensionID,
            ownerContext: ownerContext,
            controller: controller,
            adapter: adapter,
            generation: generation,
            extensionLoadGeneration: runtimeSession.extensionLoadGeneration,
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
