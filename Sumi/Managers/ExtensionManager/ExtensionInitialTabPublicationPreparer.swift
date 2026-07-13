import Foundation
import SumiWebRuntime
import WebKit

/// Silently captures the exact initial-Tab capability used by the surrounding
/// native window transaction. All mutation is complete before the receipt is
/// returned; no WebKit lifecycle callback is emitted here.
@available(macOS 15.5, *)
@MainActor
final class ExtensionInitialTabPublicationPreparer {
    private let runtimePublicationEvidence:
        ExtensionRuntimePublicationEvidenceIssuer
    private let profileRuntime: ExtensionProfileRuntime
    private let controllerQuery: any ExtensionTabControllerQuery
    private let webViews: ExtensionExactTabWebViewQuery
    private let controllerAdmission: any ExtensionWebViewControllerAdmitting
    private let contextLoading: any ExtensionContentScriptContextLoading
    private let windowPublications: ExtensionWindowPublicationQuery
    private let adapters: ExtensionCreatedTabAdapterPublication
    private let events: any ExtensionInitialTabLifecycleEventSink
    private let extensionsLoaded: @MainActor () -> Bool
    private let diagnostics: ExtensionRuntimeDiagnostics

    init(
        runtimePublicationEvidence:
            ExtensionRuntimePublicationEvidenceIssuer,
        profileRuntime: ExtensionProfileRuntime,
        adapterStore: ExtensionBrowserAdapterStore,
        controllerQuery: any ExtensionTabControllerQuery,
        webViews: ExtensionExactTabWebViewQuery,
        controllerAdmission: any ExtensionWebViewControllerAdmitting,
        adapterResolution: ExtensionAdapterCatalog,
        contextLoading: any ExtensionContentScriptContextLoading,
        windowPublications: ExtensionWindowPublicationQuery,
        events: any ExtensionInitialTabLifecycleEventSink,
        extensionsLoaded: @escaping @MainActor () -> Bool,
        diagnostics: ExtensionRuntimeDiagnostics
    ) {
        self.runtimePublicationEvidence = runtimePublicationEvidence
        self.profileRuntime = profileRuntime
        self.controllerQuery = controllerQuery
        self.webViews = webViews
        self.controllerAdmission = controllerAdmission
        self.contextLoading = contextLoading
        self.windowPublications = windowPublications
        self.events = events
        self.extensionsLoaded = extensionsLoaded
        self.diagnostics = diagnostics
        adapters = ExtensionCreatedTabAdapterPublication(
            store: adapterStore,
            resolution: adapterResolution
        )
    }

    func prepare(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        runtime: ExtensionManagerRuntime,
        windowRegistry: any ExtensionWindowQuery,
        reason: String
    ) -> ExtensionInitialTabPublicationReceipt? {
        guard extensionsLoaded(),
              window.isIncognito == false,
              tab.isEphemeral == false,
              let windowProfileID = profileRuntime.resolvedProfileId(
                  for: window,
                  runtime: runtime
              ),
              profileRuntime.resolvedProfileId(for: tab, runtime: runtime)
                == windowProfileID,
              contextLoading.profileHasLoadedContentScriptContexts(
                  profileId: windowProfileID
              ),
              let profile = runtime.profile(windowProfileID),
              webView.configuration.websiteDataStore === profile.dataStore,
              webViews.liveWebView(for: tab) === webView,
              let controller = controllerQuery.existingController(for: tab),
              controllerAdmission.admit(
                  controller,
                  profileID: windowProfileID,
                  to: webView,
                  for: tab
              ).isUsable,
              profileRuntime.controller(for: windowProfileID) === controller,
              webView.configuration.webExtensionController === controller,
              exactResidenceMatches(
                  window: window,
                  tab: tab,
                  webView: webView
              )
        else {
            return nil
        }

        let dataStore = profile.dataStore
        let runtimePublication = runtimePublicationEvidence.issue()
        let generation = runtimePublication.tabPublication
        let stateToken = tab.extensionPageRuntimeOwner
            .prepareForWindowPrepublication(generation: generation)
        guard let preparedAdapter = adapters.prepare(for: tab) else {
            _ = tab.extensionPageRuntimeOwner.rollbackWindowPrepublication(
                stateToken
            )
            return nil
        }

        let evidence = ExtensionInitialTabPublicationEvidence(
            window: window,
            tab: tab,
            webView: webView,
            profile: profile,
            dataStore: dataStore,
            profileID: windowProfileID,
            runtimePublication: runtimePublication,
            contextBindingGeneration: profileRuntime
                .contextBindingGeneration(for: windowProfileID),
            controller: controller,
            adapter: preparedAdapter.adapter,
            createdAdapter: preparedAdapter.created,
            stateToken: stateToken,
            reason: reason
        )
        let validator = ExtensionInitialTabPublicationValidator(
            runtimePublicationEvidence: runtimePublicationEvidence,
            profileRuntime: profileRuntime,
            controllerQuery: controllerQuery,
            webViews: webViews,
            contextLoading: contextLoading,
            windowRegistry: windowRegistry,
            windowPublications: windowPublications,
            adapters: adapters,
            extensionsLoaded: extensionsLoaded
        )
        let retirement = ExtensionInitialTabPublicationRetirement(
            events: events,
            adapters: adapters
        )
        guard validator.preparedEvidenceIsCurrent(
            evidence,
            requiresPublishedWindow: false
        ) else {
            let restored = tab.extensionPageRuntimeOwner
                .rollbackWindowPrepublication(stateToken)
            if restored {
                retirement.removePreparedAdapter(evidence)
            }
            return nil
        }
        return ExtensionInitialTabPublicationReceipt(
            validator: validator,
            retirement: retirement,
            diagnostics: diagnostics,
            evidence: evidence
        )
    }

    private func exactResidenceMatches(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView
    ) -> Bool {
        guard window.currentTabId == tab.id,
              webView.owningTab === tab,
              window.tabManager?.tabCollectionMembershipOwner.tab(
                  for: tab.id
              ) === tab,
              case .window(let trackedOwner) = tab.webViewSession
                .residence(of: webView)
        else {
            return false
        }
        return trackedOwner == TrackedWebViewOwner(
            tabID: tab.id,
            windowID: window.id
        )
    }
}
