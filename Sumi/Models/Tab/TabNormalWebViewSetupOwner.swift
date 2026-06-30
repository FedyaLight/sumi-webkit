import Foundation
import WebKit

@MainActor
final class TabNormalWebViewSetupOwner {
    func setupWebView(
        context: TabNormalWebViewRuntimeContext,
        provisioningOwner: TabWebViewProvisioningOwner
    ) {
        context.beginSuspendedRestoreIfNeeded()
        let reusableExistingWebView = context.parkedWebView()
        var didReuseExistingWebView = false
        var didCreateAuxiliaryOverrideWebView = false

        guard let profile = context.resolveProfile() else {
            context.deferWebViewCreationUntilProfileAvailable()
            return
        }

        let configurationContext = context.configurationContext()
        let auxiliaryOverrideConfiguration = context.webViewConfigurationOwner.auxiliaryOverrideConfiguration(
            for: profile,
            context: configurationContext
        )

        if let existingWebView = reusableExistingWebView {
            if canReuseAsNormalTabWebView(existingWebView, context: context) {
                context.adoptParkedWebViewAsCurrent(existingWebView)
                didReuseExistingWebView = true
                let replaceNormalTabUserScripts = context.replaceNormalTabUserScripts
                let currentURL = context.currentURL
                Task { @MainActor [weak existingWebView] in
                    guard let existingWebView else { return }
                    await replaceNormalTabUserScripts(
                        existingWebView.configuration.userContentController,
                        currentURL()
                    )
                }
            } else {
                context.cleanupCloneWebView(existingWebView)
                context.clearParkedExistingWebView()
            }
        }

        if !context.hasCurrentWebView {
            if let auxiliaryOverrideConfiguration {
                configurationContext.prepareWebViewConfigurationForExtensionRuntime(
                    auxiliaryOverrideConfiguration,
                    profile.id,
                    "Tab.setupWebView.configuration"
                )
                provisioningOwner.createAuxiliaryOverrideWebView(
                    auxiliaryOverrideConfiguration,
                    context: context,
                    currentURL: context.currentURL(),
                    reason: "Tab.setupWebView"
                )
                didCreateAuxiliaryOverrideWebView = true
            } else if let normalWebView = provisioningOwner.makeNormalTabWebView(
                context: context,
                reason: "Tab.setupWebView"
            ) {
                context.replaceUntrackedWebView(normalWebView)
            }
        }

        if let webView = context.currentWebView() {
            if didReuseExistingWebView || !(webView is FocusableWKWebView) {
                context.ownedWebViewPreparationOwner.prepareReusedOrExternallyCreatedWebView(webView)
            }
        }

        if let webView = context.currentWebView() {
            context.ownedWebViewPreparationOwner.applyOwnedTabWebViewNavigationPreferences(to: webView)
        }

        let shouldDelayInitialNormalTabRuntimeRegistration =
            shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: context.isPopupHost(),
                hasExistingWebView: context.hasParkedWebView,
                didCreateAuxiliaryOverrideWebView: didCreateAuxiliaryOverrideWebView,
                url: context.currentURL()
            )

        if shouldDelayInitialNormalTabRuntimeRegistration == false {
            provisioningOwner.registerNormalTabWithExtensionRuntimeIfNeeded(
                context: context,
                reason: "Tab.setupWebView"
            )
        }

        if didCreateAuxiliaryOverrideWebView,
           ExtensionUtils.isExtensionOwnedURL(context.currentURL()),
           let webView = context.currentWebView() {
            loadExtensionOwnedInitialURL(context.currentURL(), on: webView, context: context)
            context.finishSuspendedRestoreIfNeeded()
            return
        }

        if shouldDelayInitialNormalTabRuntimeRegistration {
            let initialWebView = context.currentWebView()
            let hasInitialUserContentController = initialWebView?.configuration
                .userContentController
                .sumiNormalTabUserContentController != nil
            context.scheduleInitialDocumentRuntimeHandoff(
                initialWebView,
                context.currentURL(),
                profile.id,
                "Tab.setupWebView.beforeInitialLoad",
                hasInitialUserContentController
                    ? .currentWebViewIdentity
                    : .noExistingWebView
            )
        }

        context.finishSuspendedRestoreIfNeeded()
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

    private func loadExtensionOwnedInitialURL(
        _ targetURL: URL,
        on webView: WKWebView,
        context: TabNormalWebViewRuntimeContext
    ) {
        var request = URLRequest(url: targetURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30.0
        context.loadMainFrameRequest(webView, request)
        context.applyCachedFaviconOrPlaceholder(targetURL)
    }

    private func canReuseAsNormalTabWebView(
        _ webView: WKWebView,
        context: TabNormalWebViewRuntimeContext
    ) -> Bool {
        context.webViewConfigurationOwner.canReuseAsNormalTabWebView(
            webView,
            fallbackURL: context.currentURL(),
            tabId: context.tabId,
            profile: context.resolveProfile(),
            context: context.configurationContext(),
            reloadPolicyStateOwner: context.reloadPolicyStateOwner
        )
    }
}
