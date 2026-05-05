import Combine
import BrowserServicesKit
import Foundation
import UserScript
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
    func createPopupWebViewFromWebKitConfiguration(
        _ configuration: WKWebViewConfiguration,
        currentURL: URL?,
        isExtensionOriginated: Bool,
        reason: String
    ) -> WKWebView {
        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        _webView = webView

        installNavigationDelegate(on: webView)
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.setValue(true, forKey: "drawsBackground")
        webView.owningTab = self
        SumiUserAgent.apply(to: webView)
        SharedVisitedLinkStoreProvider.shared.enableVisitedLinkRecording(on: webView)

        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            webView.isInspectable = true
        }

        webView.allowsLinkPreview = true
        webView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        installRuntimeObservers(on: webView)

        if isExtensionOriginated {
            browserManager?.extensionsModule.prepareWebViewForExtensionRuntime(
                webView,
                currentURL: currentURL,
                reason: reason
            )
        }

        return webView
    }

    /// Assigns the primary WebView to a specific window to avoid orphan runtime instances.
    func assignWebViewToWindow(_ webView: WKWebView, windowId: UUID) {
        _webView = webView
        primaryWindowId = windowId
        installNavigationDelegate(on: webView)
        installRuntimeObservers(on: webView)
    }

    /// Installs the Tab-owned runtime observers on WebViews created outside
    /// `Tab.setupWebView()`, for example by `WebViewCoordinator`.
    func installRuntimeObservers(on webView: WKWebView) {
        setupNavigationStateObservers(for: webView)
        bindAudioState(to: webView)
        applyRestoredNavigationState()
    }

    /// Creates a fully configured normal-tab WebView. This is the single
    /// construction path for primary and clone normal-tab runtimes.
    func makeNormalTabWebView(reason: String) -> WKWebView? {
        guard let configuration = normalTabWebViewConfiguration(reason: reason) else {
            return nil
        }

        browserManager?.extensionsModule.prepareWebViewConfigurationForExtensionRuntime(
            configuration,
            reason: "\(reason).configuration"
        )

        let webView = FocusableWKWebView(frame: .zero, configuration: configuration)
        configureNormalTabWebView(webView, reason: reason)
        return webView
    }

    func configureNormalTabWebView(_ webView: FocusableWKWebView, reason: String) {
        installNavigationDelegate(on: webView)
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.setValue(true, forKey: "drawsBackground")
        webView.owningTab = self
        SumiUserAgent.apply(to: webView)
        SharedVisitedLinkStoreProvider.shared.enableVisitedLinkRecording(on: webView)

        if RuntimeDiagnostics.isDeveloperInspectionEnabled {
            webView.isInspectable = true
        }

        webView.allowsLinkPreview = true
        webView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
        webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true

        installRuntimeObservers(on: webView)
        if let scriptsProvider = webView.configuration.userContentController.sumiNormalTabUserScriptsProvider {
            ensureFaviconsTabExtension(using: scriptsProvider.faviconScripts)
        }

        browserManager?.extensionsModule.prepareWebViewForExtensionRuntime(
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
           browserManager.currentTab(for: windowState)?.id == id
        {
            browserManager.extensionsModule.notifyTabActivatedIfLoaded(
                newTab: self,
                previous: nil
            )
        }
    }

    // MARK: - WebView Runtime

    func normalTabUserScriptsProvider(for targetURL: URL?) -> SumiNormalTabUserScripts {
        SumiNormalTabUserScripts(managedUserScripts: normalTabManagedUserScripts(for: targetURL))
    }

    func normalTabManagedUserScripts(for targetURL: URL?) -> [UserScript] {
        var scripts = normalTabCoreUserScripts()
        scripts.append(contentsOf: browserManager?.extensionsModule.normalTabUserScripts() ?? [])

        if let targetURL {
            scripts.append(
                contentsOf: browserManager?.userscriptsModule.normalTabUserScripts(
                    for: targetURL,
                    webViewId: id,
                    profileId: resolveProfile()?.id ?? profileId,
                    isEphemeral: isEphemeral
                ) ?? []
            )
        }

        return scripts
    }

    func replaceNormalTabUserScripts(
        on userContentController: WKUserContentController,
        for targetURL: URL?
    ) async {
        guard let provider = userContentController.sumiNormalTabUserScriptsProvider,
              let controller = userContentController as? UserContentController
        else { return }

        provider.replaceManagedUserScripts(normalTabManagedUserScripts(for: targetURL))
        await PerformanceTrace.withInterval("Tab.replaceNormalTabUserScripts") {
            await controller.replaceUserScripts(with: provider)
        }
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

        guard let profile = resolveProfile() else {
            deferNormalTabWebViewCreationUntilProfileAvailable()
            return
        }

        let auxiliaryOverrideConfiguration = webViewConfigurationOverride.map { override in
            BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
                from: override,
                for: profile,
                surface: .extensionOptions,
                additionalUserScripts: override.userContentController.userScripts
            )
        }

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
                    reason: "Tab.setupWebView.configuration"
                )
                let newWebView = FocusableWKWebView(frame: .zero, configuration: auxiliaryOverrideConfiguration)
                _webView = newWebView
                configureAuxiliaryOverrideWebView(newWebView, reason: "Tab.setupWebView")
            } else {
                _webView = makeNormalTabWebView(reason: "Tab.setupWebView")
            }
        }

        if let webView = _webView {
            if didReuseExistingWebView || !(webView is FocusableWKWebView) {
                SharedVisitedLinkStoreProvider.shared.enableVisitedLinkRecording(on: webView)
                installNavigationDelegate(on: webView)
                webView.uiDelegate = self
                webView.allowsBackForwardNavigationGestures = true
                webView.allowsMagnification = true
                installRuntimeObservers(on: webView)
                if let scriptsProvider = webView.configuration.userContentController.sumiNormalTabUserScriptsProvider {
                    ensureFaviconsTabExtension(using: scriptsProvider.faviconScripts)
                }
            }
        }

        if reusableExistingWebView == nil {
            if let webView = _webView, webViewConfigurationOverride != nil {
                SumiUserAgent.apply(to: webView)
                webView.setValue(true, forKey: "drawsBackground")
            }
        }

        if let webView = _webView {
            if RuntimeDiagnostics.isDeveloperInspectionEnabled {
                webView.isInspectable = true
            }

            webView.allowsLinkPreview = true
            webView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
            webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
        }

        registerNormalTabWithExtensionRuntimeIfNeeded(reason: "Tab.setupWebView")

        if !isPopupHost && _existingWebView == nil {
            if let controller = _webView?.configuration.userContentController as? UserContentController {
                Task { @MainActor [weak self] in
                    await PerformanceTrace.withInterval("ContentBlocking.assetsInstallWait") {
                        await controller.awaitContentBlockingAssetsInstalled()
                    }
                    guard let self, self._existingWebView == nil else { return }
                    self.loadURL(self.url)
                }
            } else {
                loadURL(url)
            }
        }

        finishSuspendedRestoreIfNeeded()
    }

    func resolveProfile() -> Profile? {
        if let pid = profileId {
            if let windowState = browserManager?.windowRegistry?.windows.values.first(where: { window in
                window.ephemeralTabs.contains(where: { $0.id == self.id })
            }),
               let ephemeralProfile = windowState.ephemeralProfile,
               ephemeralProfile.id == pid
            {
                return ephemeralProfile
            }

            if let profile = browserManager?.profileManager.profiles.first(where: { $0.id == pid }) {
                return profile
            }
        }

        if let sid = spaceId,
           let space = browserManager?.tabManager.spaces.first(where: { $0.id == sid }),
           let pid = space.profileId,
           let profile = browserManager?.profileManager.profiles.first(where: { $0.id == pid })
        {
            return profile
        }

        if let currentProfile = browserManager?.currentProfile {
            return currentProfile
        }
        return browserManager?.profileManager.profiles.first
    }

    func applyWebViewConfigurationOverride(_ configuration: WKWebViewConfiguration) {
        let isolatedConfiguration = BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
            from: configuration,
            surface: .extensionOptions,
            additionalUserScripts: configuration.userContentController.userScripts
        )
        browserManager?.extensionsModule.prepareWebViewConfigurationForExtensionRuntime(
            isolatedConfiguration,
            reason: "Tab.applyWebViewConfigurationOverride"
        )
        webViewConfigurationOverride = isolatedConfiguration
    }

    private func normalTabWebViewConfiguration(reason: String) -> WKWebViewConfiguration? {
        guard let profile = resolveProfile() else {
            RuntimeDiagnostics.emit(
                "[Tab] Unable to create normal WebView during \(reason); profile is unresolved."
            )
            deferNormalTabWebViewCreationUntilProfileAvailable()
            return nil
        }

        let trackingProtectionDecision = browserManager?.trackingProtectionModule
            .normalTabContentBlockingDecision(for: url)
        if let trackingProtectionDecision {
            noteTrackingProtectionAttachmentApplied(
                trackingProtectionDecision.attachmentState
            )
        }

        let configuration = BrowserConfiguration.shared.normalTabWebViewConfiguration(
            for: profile,
            url: url,
            autoplayPolicy: BrowserConfiguration.shared.resolvedAutoplayPolicy(
                for: url,
                profile: profile
            ),
            userScriptsProvider: normalTabUserScriptsProvider(for: url),
            contentBlockingService: trackingProtectionDecision?.contentBlockingService
        )
        return configuration
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
        guard webView.configuration.sumiIsNormalTabWebViewConfiguration else {
            return false
        }
        guard let profile = resolveProfile(),
              webView.configuration.websiteDataStore === profile.dataStore
        else {
            return false
        }
        guard let provider = webView.configuration.userContentController.sumiNormalTabUserScriptsProvider else {
            return false
        }
        let suspensionContext = "sumiTabSuspension_\(id.uuidString)"
        return provider.userScripts.contains { script in
            script.source.contains(suspensionContext)
        }
    }

    private func configureAuxiliaryOverrideWebView(_ webView: FocusableWKWebView, reason: String) {
        installNavigationDelegate(on: webView)
        webView.uiDelegate = self
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = true
        webView.setValue(true, forKey: "drawsBackground")
        webView.owningTab = self
        SumiUserAgent.apply(to: webView)
        installRuntimeObservers(on: webView)
        if let scriptsProvider = webView.configuration.userContentController.sumiNormalTabUserScriptsProvider {
            ensureFaviconsTabExtension(using: scriptsProvider.faviconScripts)
        }
        browserManager?.extensionsModule.prepareWebViewForExtensionRuntime(
            webView,
            currentURL: url,
            reason: reason
        )
    }
}
