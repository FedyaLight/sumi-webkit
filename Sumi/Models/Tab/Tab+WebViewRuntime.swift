import Combine
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
        if _webView == nil {
            setupWebView()
        }
        return _webView
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
        let webView = AuxiliaryWebViewFactory.makeWebViewPreservingWebKitConfiguration(configuration)
        _webView = webView

        ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
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
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        _webView = webView

        ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: currentURL,
            reason: reason,
            installFaviconRuntime: false,
            prepareExtensionRuntime: isExtensionOriginated
        )

        return webView
    }

    /// Assigns the primary WebView to a specific window to avoid orphan runtime instances.
    func assignWebViewToWindow(_ webView: WKWebView, windowId: UUID) {
        _webView = webView
        primaryWindowId = windowId
        ownedWebViewPreparationOwner.prepareAssignedWebView(webView)
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
        let startupTrace = StartupPerformanceTrace.firstWebViewCreationStarted()
        defer {
            StartupPerformanceTrace.firstWebViewCreationFinished(startupTrace)
        }

        guard let configuration = normalTabWebViewConfiguration(reason: reason) else {
            return nil
        }

        browserManager?.extensionsModule.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            profileId: resolveProfile()?.id ?? profileId,
            reason: "\(reason).configuration"
        )
        prepareConfiguration?(configuration)

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        configureNormalTabWebView(webView, reason: reason)
        return webView
    }

    func configureNormalTabWebView(_ webView: FocusableWKWebView, reason: String) {
        ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: url,
            reason: reason
        )
    }

    func registerNormalTabWithExtensionRuntimeIfNeeded(reason: String) {
        browserManager?.extensionsModule.registerTabWithExtensionRuntimeIfLoaded(
            self,
            reason: reason
        )

        if let browserManager,
           let windowId = primaryWindowId,
           let windowState = browserManager.windowRegistry?.windows[windowId],
           browserManager.currentTab(for: windowState)?.id == id {
            browserManager.extensionsModule.notifyTabActivatedIfLoaded(
                newTab: self,
                previous: nil
            )
        }
    }

    // MARK: - WebView Runtime

    func normalTabUserScriptsProvider(for targetURL: URL?) -> SumiNormalTabUserScripts {
        webViewConfigurationOwner.normalTabUserScriptsProvider(
            for: targetURL,
            coreUserScripts: normalTabCoreUserScripts(),
            tabId: id,
            profileIdProvider: { self.resolveProfile()?.id ?? self.profileId },
            browserManager: browserManager,
            isEphemeral: isEphemeral
        )
    }

    func normalTabManagedUserScripts(for targetURL: URL?) -> [SumiUserScript] {
        webViewConfigurationOwner.normalTabManagedUserScripts(
            for: targetURL,
            coreUserScripts: normalTabCoreUserScripts(),
            tabId: id,
            profileIdProvider: { self.resolveProfile()?.id ?? self.profileId },
            browserManager: browserManager,
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
        beginSuspendedRestoreIfNeeded()
        let reusableExistingWebView = _existingWebView
        var didReuseExistingWebView = false
        var didCreateAuxiliaryOverrideWebView = false

        guard let profile = resolveProfile() else {
            deferNormalTabWebViewCreationUntilProfileAvailable()
            return
        }

        let auxiliaryOverrideConfiguration = webViewConfigurationOwner.auxiliaryOverrideConfiguration(
            for: profile,
            browserManager: browserManager
        )

        if let existingWebView = reusableExistingWebView {
            if canReuseAsNormalTabWebView(existingWebView) {
                _webView = existingWebView
                didReuseExistingWebView = true
                Task { @MainActor [weak self, weak existingWebView] in
                    guard let self, let existingWebView else { return }
                    await self.replaceNormalTabUserScripts(
                        on: existingWebView.configuration.userContentController,
                        for: self.url
                    )
                }
            } else {
                cleanupCloneWebView(existingWebView)
                _existingWebView = nil
            }
        }

        if _webView == nil {
            if let auxiliaryOverrideConfiguration {
                browserManager?.extensionsModule.prepareWebViewConfigurationForExtensionRuntime(
                    auxiliaryOverrideConfiguration,
                    profileId: resolveProfile()?.id ?? profileId,
                    reason: "Tab.setupWebView.configuration"
                )
                let newWebView = FocusableWKWebView(frame: .zero, configuration: auxiliaryOverrideConfiguration)
                _webView = newWebView
                didCreateAuxiliaryOverrideWebView = true
                configureAuxiliaryOverrideWebView(newWebView, reason: "Tab.setupWebView")
            } else {
                _webView = makeNormalTabWebView(reason: "Tab.setupWebView")
            }
        }

        if let webView = _webView {
            if didReuseExistingWebView || !(webView is FocusableWKWebView) {
                ownedWebViewPreparationOwner.prepareReusedOrExternallyCreatedWebView(webView)
            }
        }

        if let webView = _webView {
            ownedWebViewPreparationOwner.applyOwnedTabWebViewNavigationPreferences(to: webView)
        }

        let shouldDelayInitialNormalTabRuntimeRegistration =
            webViewConfigurationOwner.shouldDelayInitialNormalTabRuntimeRegistration(
                isPopupHost: isPopupHost,
                hasExistingWebView: _existingWebView != nil,
                didCreateAuxiliaryOverrideWebView: didCreateAuxiliaryOverrideWebView,
                url: url
            )

        if shouldDelayInitialNormalTabRuntimeRegistration == false {
            registerNormalTabWithExtensionRuntimeIfNeeded(reason: "Tab.setupWebView")
        }

        if didCreateAuxiliaryOverrideWebView,
           ExtensionUtils.isExtensionOwnedURL(url),
           let webView = _webView {
            loadExtensionOwnedInitialURL(url, on: webView)
            finishSuspendedRestoreIfNeeded()
            return
        }

        if shouldDelayInitialNormalTabRuntimeRegistration {
            let initialWebView = _webView
            let hasInitialUserContentController = initialWebView?.configuration
                .userContentController
                .sumiNormalTabUserContentController != nil
            NormalTabInitialDocumentRuntimeHandoff.scheduleTabSetupInitialLoad(
                tab: self,
                webView: initialWebView,
                targetURL: url,
                profileId: resolveProfile()?.id ?? profileId,
                registrationReason: "Tab.setupWebView.beforeInitialLoad",
                registrationGuard: hasInitialUserContentController
                    ? .currentWebViewIdentity
                    : .noExistingWebView
            )
        }

        finishSuspendedRestoreIfNeeded()
    }

    private func loadExtensionOwnedInitialURL(_ targetURL: URL, on webView: WKWebView) {
        var request = URLRequest(url: targetURL)
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 30.0
        performMainFrameNavigation(on: webView) { resolvedWebView in
            resolvedWebView.load(request)
        }
        applyCachedFaviconOrPlaceholder(for: targetURL)
    }

    func resolveProfile() -> Profile? {
        if let pid = profileId {
            if let windowState = browserManager?.windowRegistry?.windows.values.first(where: { window in
                window.ephemeralTabs.contains(where: { $0.id == self.id })
            }),
               let ephemeralProfile = windowState.ephemeralProfile,
               ephemeralProfile.id == pid {
                return ephemeralProfile
            }

            if let profile = browserManager?.profileManager.profiles.first(where: { $0.id == pid }) {
                return profile
            }
        }

        if let sid = spaceId,
           let space = browserManager?.tabManager.spaces.first(where: { $0.id == sid }),
           let pid = space.profileId,
           let profile = browserManager?.profileManager.profiles.first(where: { $0.id == pid }) {
            return profile
        }

        if let currentProfile = browserManager?.currentProfile {
            return currentProfile
        }
        return browserManager?.profileManager.profiles.first
    }

    func applyWebViewConfigurationOverride(_ configuration: WKWebViewConfiguration) {
        webViewConfigurationOwner.applyWebViewConfigurationOverride(
            configuration,
            profileId: resolveProfile()?.id ?? profileId,
            browserManager: browserManager
        )
    }

    private func normalTabWebViewConfiguration(reason: String) -> WKWebViewConfiguration? {
        guard let profile = resolveProfile() else {
            RuntimeDiagnostics.emit(
                "[Tab] Unable to create normal WebView during \(reason); profile is unresolved."
            )
            deferNormalTabWebViewCreationUntilProfileAvailable()
            return nil
        }

        return webViewConfigurationOwner.normalTabWebViewConfiguration(
            for: url,
            profile: profile,
            userScriptsProvider: normalTabUserScriptsProvider(for: url),
            browserManager: browserManager,
            reloadPolicyStateOwner: reloadPolicyStateOwner
        )
    }

    private func deferNormalTabWebViewCreationUntilProfileAvailable() {
        guard profileAwaitCancellable == nil else { return }

        RuntimeDiagnostics.emit(
            "[Tab] No profile resolved yet; deferring WebView creation and observing currentProfile…"
        )
        profileAwaitCancellable = browserManager?
            .$currentProfile
            .receive(on: RunLoop.main)
            .sink { [weak self] value in
                guard let self else { return }
                if value != nil && self._webView == nil {
                    self.profileAwaitCancellable?.cancel()
                    self.profileAwaitCancellable = nil
                    self.setupWebView()
                }
            }
    }

    private func canReuseAsNormalTabWebView(_ webView: WKWebView) -> Bool {
        webViewConfigurationOwner.canReuseAsNormalTabWebView(
            webView,
            fallbackURL: url,
            tabId: id,
            profile: resolveProfile(),
            browserManager: browserManager,
            reloadPolicyStateOwner: reloadPolicyStateOwner
        )
    }

    private func configureAuxiliaryOverrideWebView(_ webView: FocusableWKWebView, reason: String) {
        ownedWebViewPreparationOwner.prepareCreatedFocusableWebView(
            webView,
            currentURL: url,
            reason: reason,
            enableVisitedLinkRecording: false,
            applyNavigationPreferences: false
        )
    }
}
