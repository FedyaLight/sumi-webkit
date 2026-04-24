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

    func adoptPopupWebView(_ webView: WKWebView) {
        _webView = webView
        installNavigationDelegate(on: webView)
        webView.uiDelegate = self
        installRuntimeObservers(on: webView)
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

    // MARK: - WebView Runtime

    func normalTabUserScriptsProvider(for targetURL: URL?) -> SumiNormalTabUserScripts {
        SumiNormalTabUserScripts(managedUserScripts: normalTabManagedUserScripts(for: targetURL))
    }

    func normalTabManagedUserScripts(for targetURL: URL?) -> [UserScript] {
        var scripts = normalTabCoreUserScripts()
        scripts.append(contentsOf: browserManager?.extensionManager.normalTabUserScripts() ?? [])

        if let targetURL {
            scripts.append(
                contentsOf: browserManager?.sumiScriptsManager.normalTabUserScripts(
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
        await controller.replaceUserScripts(with: provider)
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

        let configuration: WKWebViewConfiguration
        if let profile = resolveProfile() {
            if let override = webViewConfigurationOverride {
                configuration = BrowserConfiguration.shared.auxiliaryWebViewConfiguration(
                    from: override,
                    for: profile,
                    surface: .extensionOptions,
                    additionalUserScripts: override.userContentController.userScripts
                )
            } else {
                configuration = BrowserConfiguration.shared.normalTabWebViewConfiguration(
                    for: profile,
                    url: url,
                    userScriptsProvider: normalTabUserScriptsProvider(for: url)
                )
            }
        } else {
            if profileAwaitCancellable == nil {
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
            return
        }

        BrowserConfiguration.shared.applySitePermissionOverrides(
            to: configuration,
            url: url,
            profileId: resolveProfile()?.id ?? profileId
        )
        BrowserConfiguration.shared.applyMediaSessionPolicy(
            to: configuration,
            profile: resolveProfile()
        )

        if let existingWebView = reusableExistingWebView {
            _webView = existingWebView
            Task { @MainActor [weak self, weak existingWebView] in
                guard let self, let existingWebView else { return }
                await self.replaceNormalTabUserScripts(
                    on: existingWebView.configuration.userContentController,
                    for: self.url
                )
            }
        } else {
            browserManager?.extensionManager.prepareWebViewConfigurationForExtensionRuntime(
                configuration,
                reason: "Tab.setupWebView.configuration"
            )
            let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
            _webView = newWebView
            if let fv = _webView as? FocusableWKWebView {
                fv.owningTab = self
            }
        }

        if let webView = _webView {
            installNavigationDelegate(on: webView)
        }
        _webView?.uiDelegate = self
        _webView?.allowsBackForwardNavigationGestures = true
        _webView?.allowsMagnification = true

        if let webView = _webView {
            installRuntimeObservers(on: webView)
            if let scriptsProvider = webView.configuration.userContentController.sumiNormalTabUserScriptsProvider {
                ensureFaviconsTabExtension(using: scriptsProvider.faviconScripts)
            }
        }

        if reusableExistingWebView == nil {
            if let webView = _webView {
                SumiUserAgent.apply(to: webView)
            }
            _webView?.setValue(true, forKey: "drawsBackground")
        }

        if let webView = _webView {
            if #available(macOS 13.3, *), RuntimeDiagnostics.isDeveloperInspectionEnabled {
                webView.isInspectable = true
            }

            webView.allowsLinkPreview = true
            webView.configuration.preferences.isFraudulentWebsiteWarningEnabled = true
            webView.configuration.preferences.javaScriptCanOpenWindowsAutomatically = true
            browserManager?.extensionManager.prepareWebViewForExtensionRuntime(
                webView,
                currentURL: url,
                reason: "Tab.setupWebView"
            )
        }

        browserManager?.extensionManager.registerTabWithExtensionRuntime(
            self,
            reason: "Tab.setupWebView"
        )

        if let browserManager,
           let windowId = primaryWindowId,
           let windowState = browserManager.windowRegistry?.windows[windowId],
           browserManager.currentTab(for: windowState)?.id == id
        {
            browserManager.extensionManager.notifyTabActivated(
                newTab: self,
                previous: nil
            )
        }

        if !isPopupHost && _existingWebView == nil {
            if let controller = _webView?.configuration.userContentController as? UserContentController {
                Task { @MainActor [weak self] in
                    await controller.awaitContentBlockingAssetsInstalled()
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
        browserManager?.extensionManager.prepareWebViewConfigurationForExtensionRuntime(
            isolatedConfiguration,
            reason: "Tab.applyWebViewConfigurationOverride"
        )
        webViewConfigurationOverride = isolatedConfiguration
    }
}
