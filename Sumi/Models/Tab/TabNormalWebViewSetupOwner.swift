import Foundation
import WebKit

@MainActor
final class TabNormalWebViewSetupOwner {
    /// Single create-policy path for pre-window / untracked normal-tab WebViews.
    /// Order: profile defer → parked reuse → aux override → factory+replace → registration/handoff.
    @discardableResult
    func ensureUntrackedNormalWebView(
        context: TabNormalWebViewRuntimeContext,
        provisioningOwner: TabWebViewProvisioningOwner,
        reason: String
    ) -> WKWebView? {
        if context.hasCurrentWebView {
            return context.currentWebView()
        }

        context.beginSuspendedRestoreIfNeeded()
        let reusableExistingWebView = context.parkedWebView()
        var didReuseExistingWebView = false
        var didCreateAuxiliaryOverrideWebView = false

        guard let profile = context.resolveProfile() else {
            context.deferWebViewUntilProfileAvailable()
            return nil
        }

        let configurationContext = context.configurationContext()
        let auxiliaryOverrideConfiguration = context.configurationRuntime.auxiliaryOverrideConfiguration(
            profile,
            configurationContext
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
                configurationContext.prepareWebViewConfigForExtensionRuntime(
                    auxiliaryOverrideConfiguration,
                    profile.id,
                    "\(reason).configuration"
                )
                let overrideWebView = provisioningOwner.createAuxiliaryOverrideWebView(
                    auxiliaryOverrideConfiguration,
                    context: context,
                    currentURL: context.currentURL(),
                    reason: reason
                )
                context.replaceUntrackedWebView(overrideWebView)
                didCreateAuxiliaryOverrideWebView = true
            } else if let normalWebView = provisioningOwner.makeNormalTabWebView(
                context: context,
                reason: reason
            ) {
                context.replaceUntrackedWebView(normalWebView)
            }
        }

        if let webView = context.currentWebView() {
            if didReuseExistingWebView || !(webView is FocusableWKWebView) {
                context.preparationRuntime.prepareReusedOrExternallyCreatedWebView(webView)
            }
        }

        if let webView = context.currentWebView() {
            context.preparationRuntime.applyOwnedWebViewNavPreferences(webView)
        }

        let shouldDelayInitialTabRuntimeRegistration =
            shouldDelayInitialTabRuntimeRegistration(
                isPopupHost: context.isPopupHost(),
                hasExistingWebView: context.hasParkedWebView,
                didCreateAuxiliaryOverrideWebView: didCreateAuxiliaryOverrideWebView,
                url: context.currentURL()
            )

        if shouldDelayInitialTabRuntimeRegistration == false {
            provisioningOwner.registerTabWithExtensionRuntimeIfNeeded(
                context: context,
                reason: reason
            )
        }

        if didCreateAuxiliaryOverrideWebView,
           ExtensionUtils.isExtensionOwnedURL(context.currentURL()),
           let webView = context.currentWebView() {
            loadExtensionOwnedInitialURL(context.currentURL(), on: webView, context: context)
            context.finishSuspendedRestoreIfNeeded()
            return webView
        }

        if shouldDelayInitialTabRuntimeRegistration {
            let initialWebView = context.currentWebView()
            let hasInitialUserContentController = initialWebView?.configuration
                .userContentController
                .sumiNormalTabUserContentController != nil
            context.scheduleInitialDocumentRuntimeHandoff(
                initialWebView,
                context.currentURL(),
                profile.id,
                "\(reason).beforeInitialLoad",
                hasInitialUserContentController
                    ? .currentWebViewIdentity
                    : .noExistingWebView
            )
        }

        context.finishSuspendedRestoreIfNeeded()
        return context.currentWebView()
    }

    func shouldDelayInitialTabRuntimeRegistration(
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
        context.configurationRuntime.canReuseAsNormalTabWebView(
            webView,
            context.currentURL(),
            context.resolveProfile(),
            context.configurationContext()
        )
    }
}
