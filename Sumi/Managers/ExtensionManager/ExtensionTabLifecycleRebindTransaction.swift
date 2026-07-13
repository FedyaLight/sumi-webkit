import Foundation
import WebKit

/// Performs the exact close -> controller reconciliation -> open sequence
/// needed before an injectable committed navigation. The open claim is
/// tombstoned before WebKit receives didCloseTab.
@available(macOS 15.5, *)
@MainActor
final class ExtensionTabLifecycleRebindTransaction {
    private weak var runtimeSession: ExtensionRuntimeSession?
    private weak var profileRuntime: ExtensionProfileRuntime?
    private weak var tabs: (any ExtensionTabQuery)?
    private weak var profiles: (any ExtensionTabProfileResolving)?
    private weak var adapters: ExtensionBrowserAdapterStore?
    private weak var adapterResolver: (any ExtensionTabAdapterResolving)?
    private weak var controllers: (any ExtensionTabControllerQuery)?
    private weak var controllerPreparation:
        (any ExtensionTabControllerPreparing)?
    private weak var rebuildQuery:
        (any ExtensionControllerRuntimeRebuildQuery)?
    private weak var liveWebViews: (any ExtensionTabLiveWebViewQuery)?
    private weak var contextReadiness: (any ExtensionInitialDocumentReadiness)?
    private weak var deferredRegistration:
        (any ExtensionDeferredTabRegistrationScheduling)?
    private weak var registration: ExtensionNormalTabRegistration?
    private let events: ExtensionTabLifecycleEmitter

    init(
        runtimeSession: ExtensionRuntimeSession,
        profileRuntime: ExtensionProfileRuntime,
        tabs: any ExtensionTabQuery,
        profiles: any ExtensionTabProfileResolving,
        adapters: ExtensionBrowserAdapterStore,
        adapterResolver: any ExtensionTabAdapterResolving,
        controllers: any ExtensionTabControllerQuery,
        controllerPreparation: any ExtensionTabControllerPreparing,
        rebuildQuery: any ExtensionControllerRuntimeRebuildQuery,
        liveWebViews: any ExtensionTabLiveWebViewQuery,
        contextReadiness: any ExtensionInitialDocumentReadiness,
        deferredRegistration: any ExtensionDeferredTabRegistrationScheduling,
        registration: ExtensionNormalTabRegistration,
        events: ExtensionTabLifecycleEmitter
    ) {
        self.runtimeSession = runtimeSession
        self.profileRuntime = profileRuntime
        self.tabs = tabs
        self.profiles = profiles
        self.adapters = adapters
        self.adapterResolver = adapterResolver
        self.controllers = controllers
        self.controllerPreparation = controllerPreparation
        self.rebuildQuery = rebuildQuery
        self.liveWebViews = liveWebViews
        self.contextReadiness = contextReadiness
        self.deferredRegistration = deferredRegistration
        self.registration = registration
        self.events = events
    }

    func needsContentScriptRebind(_ tab: Tab) -> Bool {
        guard tabs?.extensionTab(for: tab.id) === tab else { return false }
        let profileID = profiles?.profileID(for: tab)
        let controllerNeedsRuntimeRebuild = liveWebViews?
            .extensionLiveWebView(for: tab)
            .map { webView in
                (webView as? FocusableWKWebView)?.owningTab !== tab
                    || rebuildQuery?.webViewNeedsExtensionRuntimeRebuild(
                        webView,
                        for: tab
                    ) == true
            } ?? false
        return ExtensionContentScriptBindingPolicy.needsRebind(
            documentBinding:
                tab.extensionPageRuntimeOwner.documentBindingSnapshot(),
            currentContextBindingGeneration: profileID.flatMap {
                profileRuntime?.contextBindingGeneration(for: $0)
            },
            controllerNeedsRuntimeRebuild: controllerNeedsRuntimeRebuild
        )
    }

    func reconcileOnUserGestureIfNeeded(_ tab: Tab, reason: String) {
        guard runtimeSession?.extensionsLoaded == true,
              tab.isEphemeral == false,
              needsContentScriptRebind(tab)
        else { return }
        registration?.register(tab, reason: reason)
    }

    func prepareBeforeCommittedMainFrameNavigation(
        _ tab: Tab,
        destinationURL: URL,
        reason: String
    ) {
        guard runtimeSession?.extensionsLoaded == true,
              tabs?.extensionTab(for: tab.id) === tab,
              tab.isEphemeral == false,
              ExtensionContentScriptBindingPolicy
              .isInjectableCommittedURL(destinationURL),
              tab.extensionPageRuntimeOwner
              .shouldSkipPreCommitRebindForInitialDocument() == false
        else { return }
        rebindBeforeCommittedNavigation(tab, reason: reason)
    }

    func rebindBeforeCommittedNavigation(_ tab: Tab, reason: String) {
        guard let runtimeSession,
              let profileRuntime,
              tabs?.extensionTab(for: tab.id) === tab,
              let profileID = profiles?.profileID(for: tab)
        else { return }

        controllerPreparation?.repair(
            tab,
            reason: reason,
            allowWhenExtensionsNotLoaded: false
        )
        if contextReadiness?
            .profileNeedsInitialDocumentExtensionContextLoad(
                profileId: profileID
            ) == true {
            _ = deferredRegistration?
                .scheduleDeferredTabNotificationAfterContextLoad(
                    tab,
                    profileId: profileID,
                    extensionLoadGeneration:
                        runtimeSession.extensionLoadGeneration,
                    reason: reason
                )
            return
        }

        let shouldCycle = tab.extensionPageRuntimeOwner
            .hasDocumentBindingForLifecycleRebind()
            || needsContentScriptRebind(tab)
        if shouldCycle,
           let controller = controllers?.existingController(for: tab),
           let adapter = adapterResolver?.stableAdapter(for: tab),
           adapter.represents(tab) {
            let extensionLoadGeneration = runtimeSession.extensionLoadGeneration
            let openGeneration = runtimeSession.tabOpenNotificationGeneration
            let contextGeneration = profileRuntime
                .contextBindingGeneration(for: profileID)
            if tab.extensionPageRuntimeOwner
                .claimDidOpenTabNotificationForClose(
                    generation: openGeneration
                ) {
                events.emitDidCloseTab(
                    tab,
                    controller: controller,
                    adapter: adapter
                )
                guard runtimeSession.extensionLoadGeneration
                        == extensionLoadGeneration,
                      runtimeSession.tabOpenNotificationGeneration
                        == openGeneration,
                      tabs?.extensionTab(for: tab.id) === tab,
                      profiles?.profileID(for: tab) == profileID,
                      profileRuntime.contextBindingGeneration(for: profileID)
                        == contextGeneration,
                      profileRuntime.controller(for: profileID) === controller,
                      adapters?.existingTabAdapter(for: tab.id) === adapter,
                      adapter.represents(tab),
                      tab.extensionPageRuntimeOwner
                        .canPublishFutureOpenNotification()
                else {
                    return
                }
            }
        }
        registration?.register(tab, reason: reason)
    }
}
