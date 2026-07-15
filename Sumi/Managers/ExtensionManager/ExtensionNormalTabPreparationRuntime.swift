import Foundation
import WebKit

@available(macOS 15.5, *)
@MainActor
struct ExtensionNormalTabPreparationRuntime {
    let userScripts: [SumiPageScript]
    private let configurations: ExtensionWebViewConfigurationPreparation
    private let lifecycle:
        ExtensionBrowserAttachmentAuthority.NormalTabLifecycle
    private let requestedTabs:
        ExtensionBrowserAttachmentAuthority.RequestedTabs

    init(
        userScripts: [SumiPageScript],
        configurations: ExtensionWebViewConfigurationPreparation,
        lifecycle: ExtensionBrowserAttachmentAuthority.NormalTabLifecycle,
        requestedTabs: ExtensionBrowserAttachmentAuthority.RequestedTabs
    ) {
        self.userScripts = userScripts
        self.configurations = configurations
        self.lifecycle = lifecycle
        self.requestedTabs = requestedTabs
    }

    func prepareConfiguration(
        _ configuration: WKWebViewConfiguration,
        profileID: UUID?,
        reason: String
    ) {
        configurations.prepareWebViewConfigForExtensionRuntime(
            configuration,
            profileId: profileID,
            reason: reason
        )
    }

    func prepareWebView(
        _ webView: WKWebView,
        currentURL: URL?,
        reason: String
    ) {
        lifecycle.prepareWebView(
            webView,
            currentURL: currentURL,
            reason: reason
        )
    }

    func preparePageNavigation(
        _ tab: Tab,
        targetURL: URL,
        reason: String
    ) -> TabWebViewReplacementOutcome {
        requestedTabs.preparePageNavigation(
            tab,
            targetURL: targetURL,
            reason: reason
        )
    }

    func register(_ tab: Tab, reason: String) {
        lifecycle.register(tab, reason: reason)
    }

    func registerCreatedTab(_ tab: Tab, reason: String) {
        requestedTabs.registerCreatedTab(tab, reason: reason)
    }

    func prepareInitialPublication(
        window: BrowserWindowState,
        tab: Tab,
        webView: FocusableWKWebView,
        reason: String
    ) -> InitialTabExtensionPreparation {
        requestedTabs.prepareInitialPublication(
            window: window,
            tab: tab,
            webView: webView,
            reason: reason
        )
    }
}
