import Foundation
import WebKit

extension Tab {
    // MARK: - WebView Ownership

    /// Returns the WebView only after it has been attached to a concrete window.
    var assignedWebView: WKWebView? {
        primaryWindowId != nil ? _webView : nil
    }

    /// Ensures a WebView exists, triggering lazy initialization if needed.
    /// Prefer `existingWebView` for read-only checks that should not create a WebView.
    @discardableResult
    func ensureWebView() -> WKWebView? {
        webViewProvisioningOwner.ensureWebView(for: self)
    }

    /// Returns the current WebView without triggering lazy initialization.
    var existingWebView: WKWebView? {
        _webView
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
            tab: self,
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
            tab: self,
            currentURL: currentURL,
            isExtensionOriginated: isExtensionOriginated,
            reason: reason
        )
    }

    /// Assigns the primary WebView to a specific window to avoid orphan runtime instances.
    func assignWebViewToWindow(_ webView: WKWebView, windowId: UUID) {
        webViewProvisioningOwner.assignWebViewToWindow(webView, tab: self, windowId: windowId)
    }

    /// Installs the Tab-owned runtime observers on WebViews created outside
    /// `Tab.setupWebView()`, for example by `WebViewCoordinator`.
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
            for: self,
            reason: reason,
            prepareConfiguration: prepareConfiguration
        )
    }

    func configureNormalTabWebView(_ webView: FocusableWKWebView, reason: String) {
        ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(webView, currentURL: url, reason: reason)
    }

    func registerNormalTabWithExtensionRuntimeIfNeeded(reason: String) {
        webViewProvisioningOwner.registerNormalTabWithExtensionRuntimeIfNeeded(
            for: self,
            reason: reason
        )
    }

    // MARK: - WebView Runtime

    func normalTabUserScriptsProvider(for targetURL: URL?) -> SumiNormalTabUserScripts {
        webViewConfigurationOwner.normalTabUserScriptsProvider(
            for: targetURL,
            coreUserScripts: normalTabCoreUserScripts(),
            tabId: id,
            profileIdProvider: { self.resolveProfile()?.id ?? self.profileId },
            context: TabWebViewConfigurationContext.live(browserManager: browserManager),
            isEphemeral: isEphemeral
        )
    }

    func normalTabManagedUserScripts(for targetURL: URL?) -> [SumiUserScript] {
        webViewConfigurationOwner.normalTabManagedUserScripts(
            for: targetURL,
            coreUserScripts: normalTabCoreUserScripts(),
            tabId: id,
            profileIdProvider: { self.resolveProfile()?.id ?? self.profileId },
            context: TabWebViewConfigurationContext.live(browserManager: browserManager),
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
        pendingMainFrameNavigationTask?.cancel()
        pendingMainFrameNavigationTask = nil
        pendingMainFrameNavigationToken = nil
        pendingBackForwardSettleTask?.cancel()
        pendingBackForwardSettleTask = nil
        pendingMainFrameNavigationKind = nil
        pendingBackForwardNavigationContext = nil
        isFreezingNavigationStateDuringBackForwardGesture = false
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
        cancelPendingMainFrameNavigation()

        let token = UUID()
        pendingMainFrameNavigationToken = token

        let loadClosure: @MainActor (WKWebView) -> Void = { [weak self] loadedWebView in
            guard let self else { return }
            guard self.pendingMainFrameNavigationToken == token else { return }
            performLoad(loadedWebView)
            self.pendingMainFrameNavigationTask = nil
            self.pendingMainFrameNavigationToken = nil
        }

        loadClosure(webView)
    }

    func setupWebView() {
        webViewProvisioningOwner.setupWebView(for: self)
    }

    func resolveProfile() -> Profile? {
        profileResolutionOwner.resolveProfile(for: self)
    }

    func applyWebViewConfigurationOverride(_ configuration: WKWebViewConfiguration) {
        webViewProvisioningOwner.applyWebViewConfigurationOverride(
            configuration,
            for: self
        )
    }
}
