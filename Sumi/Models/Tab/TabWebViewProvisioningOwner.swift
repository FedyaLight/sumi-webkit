import Foundation
import WebKit

@MainActor
final class TabWebViewProvisioningOwner {
    @discardableResult
    func ensureWebView(for tab: Tab) -> WKWebView? {
        if tab._webView == nil {
            tab.setupWebView()
        }
        return tab._webView
    }

    @discardableResult
    func createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        tab: Tab,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = AuxiliaryWebViewFactory.makeWebViewPreservingWebKitConfiguration(configuration)
        tab.replaceUntrackedWebView(webView)

        tab.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: currentURL,
            reason: reason,
            installFaviconRuntime: false,
            prepareExtensionRuntime: isExtensionOriginated
        )

        return webView
    }

    @discardableResult
    func createPopupWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        tab: Tab,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        tab.replaceUntrackedWebView(webView)

        tab.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: currentURL,
            reason: reason,
            installFaviconRuntime: false,
            prepareExtensionRuntime: isExtensionOriginated
        )

        return webView
    }

    @discardableResult
    func createAuxiliaryOverrideWebView(
        _ configuration: WKWebViewConfiguration,
        tab: Tab,
        currentURL: URL?,
        reason: String
    ) -> WKWebView {
        let webView = AuxiliaryWebViewFactory.makeWebViewPreservingWebKitConfiguration(configuration)
        tab.replaceUntrackedWebView(webView)

        tab.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: currentURL,
            reason: reason,
            enableVisitedLinkRecording: false,
            applyNavigationPreferences: false
        )

        return webView
    }

    func assignWebViewToWindow(_ webView: WKWebView, tab: Tab, windowId: UUID) {
        tab.assignPrimaryWebView(webView, windowId: windowId)
        tab.ownedWebViewPreparationOwner.prepareAssignedWebView(webView)
    }

    @discardableResult
    func makeNormalTabWebView(
        for tab: Tab,
        reason: String,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)? = nil
    ) -> WKWebView? {
        let startupTrace = StartupPerformanceTrace.firstWebViewCreationStarted()
        defer {
            StartupPerformanceTrace.firstWebViewCreationFinished(startupTrace)
        }

        guard let profile = tab.resolveProfile() else {
            RuntimeDiagnostics.emit(
                "[Tab] Unable to create normal WebView during \(reason); profile is unresolved."
            )
            tab.profileWebViewCreationGate.deferCreationUntilProfileAvailable()
            return nil
        }

        guard let configuration = normalTabWebViewConfiguration(
            for: tab,
            profile: profile,
            reason: reason
        ) else {
            return nil
        }

        let configurationContext = TabWebViewConfigurationContext.live(browserManager: tab.browserManager)
        configurationContext.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profile.id,
            "\(reason).configuration"
        )
        prepareConfiguration?(configuration)

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        configureNormalTabWebView(webView, tab: tab, reason: reason)
        return webView
    }

    func registerNormalTabWithExtensionRuntimeIfNeeded(for tab: Tab, reason: String) {
        tab.browserManager?.extensionsModule.registerTabWithExtensionRuntimeIfLoaded(
            tab,
            reason: reason
        )

        if let browserManager = tab.browserManager,
           let windowId = tab.primaryWindowId,
           let windowState = browserManager.windowRegistry?.windows[windowId],
           browserManager.currentTab(for: windowState)?.id == tab.id {
            browserManager.extensionsModule.notifyTabActivatedIfLoaded(
                newTab: tab,
                previous: nil
            )
        }
    }

    func applyWebViewConfigurationOverride(
        _ configuration: WKWebViewConfiguration,
        for tab: Tab
    ) {
        tab.webViewConfigurationOwner.applyWebViewConfigurationOverride(
            configuration,
            profileId: tab.resolveProfile()?.id ?? tab.profileId,
            context: TabWebViewConfigurationContext.live(browserManager: tab.browserManager)
        )
    }

    private func configureNormalTabWebView(
        _ webView: FocusableWKWebView,
        tab: Tab,
        reason: String
    ) {
        tab.ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: tab.url,
            reason: reason
        )
    }

    private func normalTabWebViewConfiguration(
        for tab: Tab,
        profile: Profile,
        reason: String
    ) -> WKWebViewConfiguration? {
        return tab.webViewConfigurationOwner.normalTabWebViewConfiguration(
            for: tab.url,
            profile: profile,
            userScriptsProvider: tab.normalTabUserScriptsProvider(for: tab.url),
            context: TabWebViewConfigurationContext.live(browserManager: tab.browserManager),
            reloadPolicyStateOwner: tab.reloadPolicyStateOwner
        )
    }

}
