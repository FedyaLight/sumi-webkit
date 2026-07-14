import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionRequestedTabWebViewMaterializer {
    private weak var browserContext: (any ExtensionTabWebViewHosting)?
    private let configurationPreparation:
        any ExtensionWebViewConfigurationPreparing
    private weak var livePreparation:
        (any ExtensionLiveWebViewRuntimePreparing)?
    private let profiles: any ExtensionTabProfileResolving
    private let controllers: any ExtensionTabControllerQuery
    private let webViews: ExtensionExactTabWebViewQuery
    private let controllerAdmission: any ExtensionWebViewControllerAdmitting

    init(
        browserContext: any ExtensionTabWebViewHosting,
        configurationPreparation: any ExtensionWebViewConfigurationPreparing,
        livePreparation: any ExtensionLiveWebViewRuntimePreparing,
        profiles: any ExtensionTabProfileResolving,
        controllers: any ExtensionTabControllerQuery,
        webViews: ExtensionExactTabWebViewQuery,
        controllerAdmission: any ExtensionWebViewControllerAdmitting
    ) {
        self.browserContext = browserContext
        self.configurationPreparation = configurationPreparation
        self.livePreparation = livePreparation
        self.profiles = profiles
        self.controllers = controllers
        self.webViews = webViews
        self.controllerAdmission = controllerAdmission
    }

    func materializeNormalTabIfNeeded(
        _ tab: Tab,
        targetWindow: BrowserWindowState?
    ) {
        guard let livePreparation,
              tab.webExtensionContextOverride == nil,
              tab.requiresPrimaryWebView
        else {
            return
        }

        if let targetWindow {
            browserContext?
                .materializeVisibleExtensionTabWebViewIfNeeded(
                    tab,
                    in: targetWindow
                )
        }
        prepareNormalTabWebView(
            tab,
            targetWindow: targetWindow,
            livePreparation: livePreparation
        )
    }

    func materializeExtensionOwnedTabIfNeeded(
        _ tab: Tab,
        isActive: Bool,
        hasWindowSelection: Bool
    ) {
        guard tab.webExtensionContextOverride != nil,
              ExtensionURLIdentity.isOwned(tab.url),
              tab.isUnloaded
        else {
            return
        }
        guard isActive == false || hasWindowSelection == false else { return }
        // The requested-Tab receipt is the sole publisher for this creation
        // transaction. WebView provisioning still prepares the controller and
        // data store, but must not independently emit didOpenTab first.
        _ = tab.ensureUntrackedNormalWebViewOutcome(
            reason: "ExtensionManager.extensionRequestedOwnedTab",
            registerTabWithExtensionRuntime: false
        )
    }

    private func prepareNormalTabWebView(
        _ tab: Tab,
        targetWindow: BrowserWindowState?,
        livePreparation: any ExtensionLiveWebViewRuntimePreparing
    ) {
        let currentWebView: WKWebView?
        if let targetWindow {
            currentWebView = browserContext?
                .extensionWindowOwnedWebView(for: tab, in: targetWindow.id)
        } else {
            currentWebView = webViews.untrackedWebView(for: tab)
        }

        if let currentWebView,
           committedNormalTabWebViewIsUsable(currentWebView, for: tab) {
            livePreparation.prepareWebViewForExtensionRuntime(
                currentWebView,
                currentURL: tab.url,
                reason: "ExtensionManager.extensionRequestedNormalTab"
            )
            return
        }

        let reason = "ExtensionManager.extensionRequestedNormalTab.replacement"
        _ = browserContext?.replaceExtensionLiveWebView(
            for: tab,
            in: targetWindow,
            reason: reason,
            prepareCandidateConfiguration: { configuration, profileID in
                configurationPreparation.prepareWebViewConfigForExtensionRuntime(
                    configuration,
                    profileId: profileID,
                    reason: "\(reason).configuration"
                )
            },
            prepareCommittedReplacement: { [weak tab] webView in
                guard let tab else { return }
                livePreparation.prepareWebViewForExtensionRuntime(
                    webView,
                    currentURL: tab.url,
                    reason: reason
                )
            },
            validate: { [weak tab] webView in
                guard let tab else { return false }
                return preparedNormalTabWebViewIsUsable(
                    webView,
                    for: tab
                )
            }
        )
    }

    private func committedNormalTabWebViewIsUsable(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        guard let profileID = profiles.profileID(for: tab),
              let expectedController = controllers.existingController(for: tab),
              controllerAdmission.admit(
                  expectedController,
                  profileID: profileID,
                  to: webView,
                  for: tab
              ).isUsable
        else {
            return false
        }
        return webView.configuration.webExtensionController === expectedController
    }

    /// Replacement validation runs before the candidate becomes the Tab's
    /// canonical residence. Its authority is the exact creation transaction,
    /// so it validates immutable construction evidence without weakening the
    /// committed-WebView binder.
    private func preparedNormalTabWebViewIsUsable(
        _ webView: WKWebView,
        for tab: Tab
    ) -> Bool {
        guard webViews.isCanonical(tab),
              (webView as? FocusableWKWebView)?.owningTab === tab,
              let profileID = profiles.profileID(for: tab),
              let controller = controllers.existingController(for: tab),
              webView.configuration.webExtensionController === controller,
              webViews.isCanonical(tab),
              profiles.profileID(for: tab) == profileID,
              controllers.existingController(for: tab) === controller,
              (webView as? FocusableWKWebView)?.owningTab === tab,
              webView.configuration.webExtensionController === controller
        else { return false }
        return true
    }
}
