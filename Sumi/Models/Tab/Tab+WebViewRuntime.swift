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
        webViewProvisioningOwner.ensureWebView(context: normalWebViewRuntimeContext())
    }

    /// Returns the current WebView without triggering lazy initialization.
    var existingWebView: WKWebView? {
        currentWebView
    }

    /// Returns the current WebView without triggering lazy initialization.
    /// Use this inside runtime owners instead of the legacy `_webView` bridge.
    var currentWebView: WKWebView? {
        _webView
    }

    var hasCurrentWebView: Bool {
        currentWebView != nil
    }

    var parkedWebView: WKWebView? {
        _existingWebView
    }

    var hasParkedWebView: Bool {
        parkedWebView != nil
    }

    func currentWebViewIsIdentical(to webView: WKWebView) -> Bool {
        currentWebView === webView
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
            context: normalWebViewRuntimeContext(),
            reason: reason,
            prepareConfiguration: prepareConfiguration
        )
    }

    func configureNormalTabWebView(_ webView: FocusableWKWebView, reason: String) {
        ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(webView, currentURL: url, reason: reason)
    }

    func registerNormalTabWithExtensionRuntimeIfNeeded(reason: String) {
        webViewProvisioningOwner.registerNormalTabWithExtensionRuntimeIfNeeded(
            context: normalWebViewRuntimeContext(),
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
        navigationTransactionOwner.cancelPendingMainFrameNavigation()
    }

    func clearPendingMainFrameNavigationState() {
        navigationTransactionOwner.clearRelatedNavigationState()
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
        navigationTransactionOwner.perform(
            on: webView,
            performLoad: performLoad
        )
    }

    func setupWebView() {
        normalWebViewSetupOwner.setupWebView(
            context: normalWebViewRuntimeContext(),
            provisioningOwner: webViewProvisioningOwner
        )
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
        TabNormalWebViewRuntimeContext(
            tabId: id,
            currentURL: { [weak self, initialURL = url] in
                self?.url ?? initialURL
            },
            isPopupHost: { [weak self] in
                self?.isPopupHost ?? false
            },
            currentWebView: { [weak self] in
                self?.currentWebView
            },
            parkedWebView: { [weak self] in
                self?.parkedWebView
            },
            profileId: { [weak self, initialProfileId = profileId] in
                self?.profileId ?? initialProfileId
            },
            resolveProfile: { [weak self] in
                self?.resolveProfile()
            },
            deferWebViewCreationUntilProfileAvailable: { [weak self] in
                self?.profileWebViewCreationGate.deferCreationUntilProfileAvailable()
            },
            beginSuspendedRestoreIfNeeded: { [weak self] in
                self?.beginSuspendedRestoreIfNeeded()
            },
            finishSuspendedRestoreIfNeeded: { [weak self] in
                self?.finishSuspendedRestoreIfNeeded()
            },
            setupWebView: { [weak self] in
                self?.setupWebView()
            },
            adoptParkedWebViewAsCurrent: { [weak self] webView in
                self?.adoptParkedWebViewAsCurrent(webView)
            },
            clearParkedExistingWebView: { [weak self] in
                self?.clearParkedExistingWebView()
            },
            replaceUntrackedWebView: { [weak self] webView in
                self?.replaceUntrackedWebView(webView)
            },
            assignPrimaryWebView: { [weak self] webView, windowId in
                self?.assignPrimaryWebView(webView, windowId: windowId)
            },
            cleanupCloneWebView: { [weak self] webView in
                self?.cleanupCloneWebView(webView)
            },
            configurationContext: { [weak self] in
                TabWebViewConfigurationContext.live(browserManager: self?.browserManager)
            },
            webViewConfigurationOwner: webViewConfigurationOwner,
            ownedWebViewPreparationOwner: ownedWebViewPreparationOwner,
            reloadPolicyStateOwner: reloadPolicyStateOwner,
            normalTabUserScriptsProvider: { [weak self] targetURL in
                self?.normalTabUserScriptsProvider(for: targetURL)
                    ?? SumiNormalTabUserScripts(managedUserScripts: [])
            },
            replaceNormalTabUserScripts: { [weak self] userContentController, targetURL in
                guard let self else { return }
                await self.replaceNormalTabUserScripts(
                    on: userContentController,
                    for: targetURL
                )
            },
            loadMainFrameRequest: { [weak self] webView, request in
                self?.performMainFrameNavigation(on: webView) { resolvedWebView in
                    resolvedWebView.load(request)
                }
            },
            applyCachedFaviconOrPlaceholder: { [weak self] url in
                self?.applyCachedFaviconOrPlaceholder(for: url)
            },
            registerNormalTabWithExtensionRuntimeIfNeeded: { [weak self] reason in
                guard let self else { return }
                self.browserManager?.extensionsModule.registerTabWithExtensionRuntimeIfLoaded(
                    self,
                    reason: reason
                )

                guard let browserManager = self.browserManager,
                      let windowId = self.primaryWindowId,
                      let windowState = browserManager.windowRegistry?.windows[windowId],
                      browserManager.currentTab(for: windowState)?.id == self.id else {
                    return
                }

                browserManager.extensionsModule.notifyTabActivatedIfLoaded(
                    newTab: self,
                    previous: nil
                )
            },
            scheduleInitialDocumentRuntimeHandoff: { [weak self] webView, targetURL, profileId, registrationReason, registrationGuard in
                guard let self else { return }
                NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
                    tab: self,
                    webView: webView,
                    targetURL: targetURL,
                    profileId: profileId,
                    registrationReason: registrationReason,
                    registrationGuard: registrationGuard
                )
            }
        )
    }
}
