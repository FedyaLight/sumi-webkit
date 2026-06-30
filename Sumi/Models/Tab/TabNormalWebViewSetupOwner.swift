import Foundation
import WebKit

@MainActor
final class TabNormalWebViewSetupOwner {
    func setupWebView(for tab: Tab) {
        tab.beginSuspendedRestoreIfNeeded()
        let reusableExistingWebView = tab._existingWebView
        var didReuseExistingWebView = false
        var didCreateAuxiliaryOverrideWebView = false

        guard let profile = tab.resolveProfile() else {
            tab.profileWebViewCreationGate.deferCreationUntilProfileAvailable()
            return
        }

        let configurationContext = TabWebViewConfigurationContext.live(browserManager: tab.browserManager)
        let auxiliaryOverrideConfiguration = tab.webViewConfigurationOwner.auxiliaryOverrideConfiguration(
            for: profile,
            context: configurationContext
        )

        if let existingWebView = reusableExistingWebView {
            if canReuseAsNormalTabWebView(existingWebView, tab: tab) {
                tab.adoptParkedWebViewAsCurrent(existingWebView)
                didReuseExistingWebView = true
                Task { @MainActor [weak tab, weak existingWebView] in
                    guard let tab, let existingWebView else { return }
                    await tab.replaceNormalTabUserScripts(
                        on: existingWebView.configuration.userContentController,
                        for: tab.url
                    )
                }
            } else {
                tab.cleanupCloneWebView(existingWebView)
                tab.clearParkedExistingWebView()
            }
        }

        if tab._webView == nil {
            if let auxiliaryOverrideConfiguration {
                configurationContext.prepareWebViewConfigurationForExtensionRuntime(
                    auxiliaryOverrideConfiguration,
                    profile.id,
                    "Tab.setupWebView.configuration"
                )
                tab.webViewProvisioningOwner.createAuxiliaryOverrideWebView(
                    auxiliaryOverrideConfiguration,
                    tab: tab,
                    currentURL: tab.url,
                    reason: "Tab.setupWebView"
                )
                didCreateAuxiliaryOverrideWebView = true
            } else if let normalWebView = tab.makeNormalTabWebView(reason: "Tab.setupWebView") {
                tab.replaceUntrackedWebView(normalWebView)
            }
        }

        if let webView = tab._webView {
            if didReuseExistingWebView || !(webView is FocusableWKWebView) {
                tab.ownedWebViewPreparationOwner.prepareReusedOrExternallyCreatedWebView(webView)
            }
        }

        if let webView = tab._webView {
            tab.ownedWebViewPreparationOwner.applyOwnedTabWebViewNavigationPreferences(to: webView)
        }

        let shouldDelayInitialNormalTabRuntimeRegistration =
            shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: tab.isPopupHost,
                hasExistingWebView: tab._existingWebView != nil,
                didCreateAuxiliaryOverrideWebView: didCreateAuxiliaryOverrideWebView,
                url: tab.url
            )

        if shouldDelayInitialNormalTabRuntimeRegistration == false {
            tab.registerNormalTabWithExtensionRuntimeIfNeeded(reason: "Tab.setupWebView")
        }

        if didCreateAuxiliaryOverrideWebView,
           ExtensionUtils.isExtensionOwnedURL(tab.url),
           let webView = tab._webView {
            loadExtensionOwnedInitialURL(tab.url, on: webView, tab: tab)
            tab.finishSuspendedRestoreIfNeeded()
            return
        }

        if shouldDelayInitialNormalTabRuntimeRegistration {
            let initialWebView = tab._webView
            let hasInitialUserContentController = initialWebView?.configuration
                .userContentController
                .sumiNormalTabUserContentController != nil
            NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
                tab: tab,
                webView: initialWebView,
                targetURL: tab.url,
                profileId: profile.id,
                registrationReason: "Tab.setupWebView.beforeInitialLoad",
                registrationGuard: hasInitialUserContentController
                    ? .currentWebViewIdentity
                    : .noExistingWebView
            )
        }

        tab.finishSuspendedRestoreIfNeeded()
    }

    func shouldDelayInitialNormalTabRuntimeRegistration(
        isPopupHost: Bool,
        hasExistingWebView: Bool,
        didCreateAuxiliaryOverrideWebView: Bool,
        url: URL
    ) -> Bool {
        !isPopupHost
            && !hasExistingWebView
            && !didCreateAuxiliaryOverrideWebView
            && Self.isInitialDocumentExtensionWarmupURL(url)
    }

    static func isInitialDocumentExtensionWarmupURL(_ url: URL) -> Bool {
        let scheme = url.scheme?.lowercased()
        return scheme == "http" || scheme == "https"
    }

    private func loadExtensionOwnedInitialURL(_ targetURL: URL, on webView: WKWebView, tab: Tab) {
        var request = URLRequest(url: targetURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30.0
        tab.performMainFrameNavigation(on: webView) { resolvedWebView in
            resolvedWebView.load(request)
        }
        tab.applyCachedFaviconOrPlaceholder(for: targetURL)
    }

    private func canReuseAsNormalTabWebView(_ webView: WKWebView, tab: Tab) -> Bool {
        tab.webViewConfigurationOwner.canReuseAsNormalTabWebView(
            webView,
            fallbackURL: tab.url,
            tabId: tab.id,
            profile: tab.resolveProfile(),
            context: TabWebViewConfigurationContext.live(browserManager: tab.browserManager),
            reloadPolicyStateOwner: tab.reloadPolicyStateOwner
        )
    }
}
