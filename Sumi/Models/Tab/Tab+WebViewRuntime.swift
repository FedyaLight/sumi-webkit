import Combine
import Foundation
import WebKit

extension Tab {
    private static let tabScopedCoreScriptMessageBaseNames = [
        "linkHover",
        "commandHover",
        "commandClick",
        "SumiIdentity",
        "faviconLinks",
    ]

    static func coreScriptMessageHandlerName(
        _ baseName: String,
        for tabId: UUID
    ) -> String {
        "\(baseName)_\(tabId.uuidString)"
    }

    static func coreScriptMessageHandlerNames(for tabId: UUID) -> [String] {
        tabScopedCoreScriptMessageBaseNames.map {
            coreScriptMessageHandlerName($0, for: tabId)
        }
    }

    func coreScriptMessageHandlerName(
        _ baseName: String,
        for tabId: UUID? = nil
    ) -> String {
        Self.coreScriptMessageHandlerName(baseName, for: tabId ?? id)
    }

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
        installRuntimeObservers(on: webView)
        replaceCoreScriptMessageHandlers(on: webView.configuration.userContentController)
    }

    /// Assigns the primary WebView to a specific window to avoid orphan runtime instances.
    func assignWebViewToWindow(_ webView: WKWebView, windowId: UUID) {
        _webView = webView
        primaryWindowId = windowId
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

    func coreScriptMessageHandlerNames(for tabId: UUID) -> [String] {
        Self.coreScriptMessageHandlerNames(for: tabId)
    }

    func replaceCoreScriptMessageHandlers(on userContentController: WKUserContentController) {
        for handlerName in coreScriptMessageHandlerNames(for: id) {
            userContentController.removeScriptMessageHandler(forName: handlerName)
        }

        userContentController.add(self, name: coreScriptMessageHandlerName("linkHover"))
        userContentController.add(self, name: coreScriptMessageHandlerName("commandHover"))
        userContentController.add(self, name: coreScriptMessageHandlerName("commandClick"))
        userContentController.add(self, name: coreScriptMessageHandlerName("SumiIdentity"))
        userContentController.add(self, name: coreScriptMessageHandlerName("faviconLinks"))
        installFaviconDiscoveryScriptIfNeeded(on: userContentController)
    }

    static func faviconDiscoveryMarker(for tabId: UUID) -> String {
        "__sumiFaviconReporter_\(tabId.uuidString.replacingOccurrences(of: "-", with: "_"))"
    }

    // Ported from DuckDuckGo content-scope-scripts `injected/src/features/favicon.js`
    // pinned by apple-browsers macOS `Package.resolved` revision 454f3131bbbdc19a4bf5bc1c2aabf1725cc9f5fc.
    static func faviconDiscoveryScriptSource(
        handlerName: String,
        marker: String
    ) -> String {
        """
        (() => {
          if (window["\(marker)"]) { return; }
          window["\(marker)"] = true;

          const handler = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers["\(handlerName)"];
          if (!handler) { return; }

          let lastFavicons = null;

          const faviconKey = (favicon) => JSON.stringify([
            favicon.href || '',
            favicon.rel || '',
            favicon.type || ''
          ]);

          const sameOrderedFavicons = (lhs, rhs) => {
            if (lhs.length !== rhs.length) { return false; }
            for (let index = 0; index < lhs.length; index += 1) {
              if (faviconKey(lhs[index]) !== faviconKey(rhs[index])) { return false; }
            }
            return true;
          };

          const getFaviconList = () => {
            const target = document.head;
            if (!target) { return []; }

            const selectors = [
              "link[href][rel='favicon']",
              "link[href][rel*='icon']",
              "link[href][rel='apple-touch-icon']",
              "link[href][rel='apple-touch-icon-precomposed']"
            ];

            return Array.from(target.querySelectorAll(selectors.join(',')))
              .filter((element) => element instanceof HTMLLinkElement)
              .map((link) => {
                const href = link.href || '';
                const rel = link.getAttribute('rel') || '';
                const type = link.type || '';
                return { href, rel, type };
              });
          };

          const send = () => {
            const nextFavicons = getFaviconList();
            if (lastFavicons === null) {
              lastFavicons = nextFavicons;
              handler.postMessage({
                documentUrl: document.URL,
                favicons: nextFavicons
              });
              return;
            }

            if (sameOrderedFavicons(lastFavicons, nextFavicons)) {
              return;
            }

            const previousKeys = lastFavicons.map(faviconKey);
            const nextKeys = nextFavicons.map(faviconKey);
            const previousKeySet = new Set(previousKeys);
            const nextKeySet = new Set(nextKeys);
            const didOnlyReorder =
              previousKeys.length === nextKeys.length
              && previousKeys.every((key) => nextKeySet.has(key))
              && nextKeys.every((key) => previousKeySet.has(key));

            if (didOnlyReorder) {
              lastFavicons = nextFavicons;
              handler.postMessage({
                documentUrl: document.URL,
                favicons: nextFavicons
              });
              return;
            }

            const upserted = nextFavicons.filter((favicon) => !previousKeySet.has(faviconKey(favicon)));
            const removed = lastFavicons.filter((favicon) => !nextKeySet.has(faviconKey(favicon)));
            lastFavicons = nextFavicons;

            handler.postMessage({
              documentUrl: document.URL,
              faviconDelta: {
                upserted,
                removed
              }
            });
          };

          const monitorChanges = () => {
            const target = document.head;
            if (!target || !window.MutationObserver) { return; }

            let trailing;
            let lastEmitTime = performance.now();
            const interval = 50;

            const changeObserved = () => {
              clearTimeout(trailing);
              const currentTime = performance.now();
              const delta = currentTime - lastEmitTime;
              if (delta >= interval) {
                send();
              } else {
                trailing = setTimeout(() => {
                  send();
                }, interval);
              }
              lastEmitTime = currentTime;
            };

            const observer = new MutationObserver((mutations) => {
              for (const mutation of mutations) {
                if (mutation.type === 'attributes' && mutation.target instanceof HTMLLinkElement) {
                  changeObserved();
                  return;
                }
                if (mutation.type === 'childList') {
                  for (const addedNode of mutation.addedNodes) {
                    if (addedNode instanceof HTMLLinkElement) {
                      changeObserved();
                      return;
                    }
                  }
                  for (const removedNode of mutation.removedNodes) {
                    if (removedNode instanceof HTMLLinkElement) {
                      changeObserved();
                      return;
                    }
                  }
                }
              }
            });

            observer.observe(target, {
              attributeFilter: ['rel', 'href', 'type'],
              attributes: true,
              subtree: true,
              childList: true
            });
          };

          const start = () => {
            send();
            monitorChanges();
          };

          if (document.readyState === 'loading') {
            window.addEventListener('DOMContentLoaded', start, { once: true });
          } else {
            start();
          }
        })();
        """
    }

    private func installFaviconDiscoveryScriptIfNeeded(on userContentController: WKUserContentController) {
        let marker = Self.faviconDiscoveryMarker(for: id)
        guard userContentController.userScripts.contains(where: { $0.source.contains(marker) }) == false else {
            return
        }

        let handlerName = coreScriptMessageHandlerName("faviconLinks")
        let source = Self.faviconDiscoveryScriptSource(
            handlerName: handlerName,
            marker: marker
        )
        userContentController.addUserScript(WKUserScript(
            source: source,
            injectionTime: .atDocumentEnd,
            forMainFrameOnly: true
        ))
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
        let reusableExistingWebView = _existingWebView

        let configuration: WKWebViewConfiguration
        if let profile = resolveProfile() {
            if let override = webViewConfigurationOverride {
                configuration = (override.copy() as? WKWebViewConfiguration) ?? override
            } else {
                configuration = BrowserConfiguration.shared.cacheOptimizedWebViewConfiguration(
                    for: profile
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
            browserManager?.sumiScriptsManager.installContentController(
                existingWebView.configuration.userContentController,
                for: url,
                webViewId: id,
                profileId: resolveProfile()?.id ?? profileId,
                isEphemeral: isEphemeral
            )
        } else {
            browserManager?.extensionManager.prepareWebViewConfigurationForExtensionRuntime(
                configuration,
                reason: "Tab.setupWebView.configuration"
            )
            browserManager?.sumiScriptsManager.installContentController(
                configuration.userContentController,
                for: url,
                webViewId: id,
                profileId: resolveProfile()?.id ?? profileId,
                isEphemeral: isEphemeral
            )
            let newWebView = FocusableWKWebView(frame: .zero, configuration: configuration)
            _webView = newWebView
            if let fv = _webView as? FocusableWKWebView {
                fv.owningTab = self
            }
        }

        _webView?.navigationDelegate = self
        _webView?.uiDelegate = self
        _webView?.allowsBackForwardNavigationGestures = true
        _webView?.allowsMagnification = true

        if let webView = _webView {
            installRuntimeObservers(on: webView)
        }

        if reusableExistingWebView == nil {
            if let userContentController = _webView?.configuration.userContentController {
                replaceCoreScriptMessageHandlers(on: userContentController)
            }

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
            loadURL(url)
        }
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
        let isolatedConfiguration = BrowserConfiguration.shared.isolatedWebViewConfigurationCopy(
            from: configuration,
            websiteDataStore: configuration.websiteDataStore
        )
        browserManager?.extensionManager.prepareWebViewConfigurationForExtensionRuntime(
            isolatedConfiguration,
            reason: "Tab.applyWebViewConfigurationOverride"
        )
        webViewConfigurationOverride = isolatedConfiguration
    }
}
