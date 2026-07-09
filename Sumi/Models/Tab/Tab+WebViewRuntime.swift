import Foundation
import WebKit

extension Tab {
    // MARK: - WebView Ownership (session/registry resolve + mutator forwards)

    /// Session/registry resolve for Tab-internal owners and derived helpers.
    /// Not a public WebView SoT accessor — live lookup stays on routing/session.
    func resolvedCurrentWebView() -> WKWebView? {
        if hasBrowserRuntime {
            if let windowId = navigationRuntime.webViewRouting.sessionPrimaryWindowId(id)
                ?? navigationRuntime.webViewRouting.primaryTrackedWindowId(id)
                ?? webViewOwnershipOwner.localSession.primaryWindowId,
               let tracked = navigationRuntime.webViewRouting.windowOwnedWebView(id, windowId) {
                return tracked
            }
            return navigationRuntime.webViewRouting.sessionPrimaryWebView(id)
                ?? navigationRuntime.webViewRouting.sessionUntrackedWebView(id)
                ?? webViewOwnershipOwner.localSession.currentWebView
        }
        return webViewOwnershipOwner.localSession.currentWebView
    }

    /// Parked/staging WebView from session (or pre-runtime local session).
    func resolvedParkedWebView() -> WKWebView? {
        if hasBrowserRuntime {
            return navigationRuntime.webViewRouting.sessionParkedWebView(id)
                ?? webViewOwnershipOwner.localSession.parkedWebView
        }
        return webViewOwnershipOwner.localSession.parkedWebView
    }

    /// Primary window id from session/registry (or pre-runtime local session).
    func resolvedPrimaryWindowId() -> UUID? {
        if hasBrowserRuntime {
            return navigationRuntime.webViewRouting.sessionPrimaryWindowId(id)
                ?? navigationRuntime.webViewRouting.primaryTrackedWindowId(id)
                ?? webViewOwnershipOwner.localSession.primaryWindowId
        }
        return webViewOwnershipOwner.localSession.primaryWindowId
    }

    /// Window-assigned primary WebView when a primary window id is known.
    func resolvedAssignedWebView() -> WKWebView? {
        guard let windowId = resolvedPrimaryWindowId() else { return nil }
        if hasBrowserRuntime {
            return navigationRuntime.webViewRouting.windowOwnedWebView(id, windowId)
                ?? navigationRuntime.webViewRouting.sessionPrimaryWebView(id)
                ?? webViewOwnershipOwner.localSession.primaryWebView
        }
        return webViewOwnershipOwner.localSession.primaryWindowId != nil
            ? webViewOwnershipOwner.localSession.primaryWebView
            : nil
    }

    var hasCurrentWebView: Bool {
        resolvedCurrentWebView() != nil
    }

    var hasParkedWebView: Bool {
        resolvedParkedWebView() != nil
    }

    func currentWebViewIsIdentical(to webView: WKWebView) -> Bool {
        resolvedCurrentWebView() === webView
    }

    @discardableResult
    func createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        webViewProvisioningOwner.createAuxiliaryMiniWindowWebViewFromWebKitConfiguration(
            configuration,
            context: normalWebViewRuntimeContext(),
            currentURL: currentURL,
            isExtensionOriginated: isExtensionOriginated,
            reason: reason
        )
    }

    @discardableResult
    func createPopupWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        webViewProvisioningOwner.createPopupWebViewFromWebKitConfiguration(
            configuration,
            context: normalWebViewRuntimeContext(),
            currentURL: currentURL,
            isExtensionOriginated: isExtensionOriginated,
            reason: reason
        )
    }

    /// Assigns the primary WebView to a specific window to avoid orphan runtime instances.
    func assignWebViewToWindow(_ webView: WKWebView, windowId: UUID) {
        webViewProvisioningOwner.assignWebViewToWindow(
            webView,
            context: normalWebViewRuntimeContext(),
            windowId: windowId
        )
    }

    /// Installs the Tab-owned runtime observers on WebViews created outside
    /// the untracked ensure path, for example by `WebViewCoordinator`.
    func installRuntimeObservers(on webView: WKWebView) {
        ownedWebViewPreparationOwner.installRuntimeObservers(on: webView)
    }

    /// Creates a fully configured normal-tab WebView. This is the single
    /// construction path for primary and clone normal-tab runtimes.
    func makeNormalTabWebView(
        reason: String,
        prepareConfiguration: ((WKWebViewConfiguration) -> Void)? = nil
    ) -> WKWebView? {
        webViewProvisioningOwner.makeNormalTabWebView(
            context: normalWebViewRuntimeContext(),
            reason: reason,
            prepareConfiguration: prepareConfiguration
        )
    }

    func configureNormalTabWebView(_ webView: FocusableWKWebView, reason: String) {
        ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(webView, currentURL: url, reason: reason)
    }

    func makeAuxiliaryOverrideTabWebView(
        configuration: WKWebViewConfiguration,
        reason: String
    ) -> WKWebView {
        let runtimeContext = normalWebViewRuntimeContext()
        let webView = AuxiliaryWebViewFactory
            .makeWebViewPreservingWebKitConfiguration(configuration)
        runtimeContext.preparationRuntime.prepareCreatedFocusableWebView(
            webView,
            runtimeContext.currentURL(),
            reason,
            .auxiliaryOverride
        )
        return webView
    }

    func registerTabWithExtensionRuntimeIfNeeded(reason: String) {
        webViewProvisioningOwner.registerTabWithExtensionRuntimeIfNeeded(
            context: normalWebViewRuntimeContext(),
            reason: reason
        )
    }

    // MARK: - WebView Runtime

    func webViewConfigurationContext() -> TabWebViewConfigurationContext {
        makeWebViewConfigurationContext()
    }

    func normalTabUserScriptsProvider(for targetURL: URL?) -> SumiNormalTabUserScripts {
        webViewConfigurationOwner.normalTabUserScriptsProvider(
            for: targetURL,
            coreUserScripts: normalTabCoreUserScripts(),
            tabId: id,
            profileIdProvider: { self.resolveProfile()?.id ?? self.profileId },
            context: webViewConfigurationContext(),
            isEphemeral: isEphemeral
        )
    }

    func normalTabManagedUserScripts(for targetURL: URL?) -> [SumiUserScript] {
        webViewConfigurationOwner.normalTabManagedUserScripts(
            for: targetURL,
            coreUserScripts: normalTabCoreUserScripts(),
            tabId: id,
            profileIdProvider: { self.resolveProfile()?.id ?? self.profileId },
            context: webViewConfigurationContext(),
            isEphemeral: isEphemeral
        )
    }

    func replaceNormalTabUserScripts(
        on userContentController: WKUserContentController,
        for targetURL: URL?
    ) async {
        guard let controller = userContentController.sumiNormalTabUserContentController,
              let provider = controller.normalTabUserScriptsProvider
        else { return }

        let managedUserScripts = normalTabManagedUserScripts(for: targetURL)
        guard provider.replaceManagedUserScriptsIfChanged(managedUserScripts) else {
            return
        }

        let signpostState = PerformanceTrace.beginInterval("Tab.replaceNormalTabUserScripts")
        defer { PerformanceTrace.endInterval("Tab.replaceNormalTabUserScripts", signpostState) }
        await controller.replaceNormalTabUserScripts(with: provider)
    }

    func cancelPendingMainFrameNavigation() {
        navigationRuntime.navigationTransactionOwner.cancelPendingMainFrameNavigation()
    }

    @available(macOS 15.5, *)
    func performMainFrameNavigationAfterHydrationIfNeeded(
        on webView: WKWebView,
        performLoad: @escaping @MainActor (WKWebView) -> Void
    ) {
        performMainFrameNavigation(
            on: webView,
            performLoad: performLoad
        )
    }

    func performMainFrameNavigation(
        on webView: WKWebView,
        performLoad: @escaping @MainActor (WKWebView) -> Void
    ) {
        navigationRuntime.navigationTransactionOwner.perform(
            on: webView,
            performLoad: performLoad
        )
    }

    /// Single create-policy path for pre-window / untracked normal-tab WebViews.
    @discardableResult
    func ensureUntrackedNormalWebView(
        reason: String = "Tab.ensureUntrackedNormalWebView"
    ) -> WKWebView? {
        normalWebViewSetupOwner.ensureUntrackedNormalWebView(
            context: normalWebViewRuntimeContext(),
            provisioningOwner: webViewProvisioningOwner,
            reason: reason
        )
    }

    /// Thin wrapper retained for call sites that historically named this `setupWebView`.
    func setupWebView() {
        _ = ensureUntrackedNormalWebView(reason: "Tab.setupWebView")
    }

    func resolveProfile() -> Profile? {
        profileResolutionOwner.resolveProfile(for: self)
    }

    func applyWebViewConfigurationOverride(_ configuration: WKWebViewConfiguration) {
        webViewProvisioningOwner.applyWebViewConfigurationOverride(
            configuration,
            context: normalWebViewRuntimeContext()
        )
    }

    func normalWebViewRuntimeContext() -> TabNormalWebViewRuntimeContext {
        normalWebViewRuntimeContextOwner.makeContext()
    }
}
