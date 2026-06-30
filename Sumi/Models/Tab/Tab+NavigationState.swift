import Foundation
import WebKit

extension Tab {
    // MARK: - Navigation Controls

    func goBack() {
        guard canGoBack else { return }
        guard let webView = _webView else { return }
        SumiWebViewNavigator.goBack(on: webView)
    }

    func goForward() {
        guard canGoForward else { return }
        guard let webView = _webView else { return }
        SumiWebViewNavigator.goForward(on: webView)
    }

    func stopLoading(on webView: WKWebView? = nil) {
        let resolvedWebView = webView ?? _webView
        resolvedWebView?.stopLoading()

        if loadingState.isLoading {
            loadingState = .idle
        }
    }

    func refresh() {
        guard !representsSumiNativeSurface else { return }
        beginLoadingPresentationIfNeeded()
        let targetURL = _webView?.url ?? url
        let protectionReloadWasRequired = isProtectionReloadRequired
        let rebuiltForConfigurationPolicy = rebuildNormalWebViewForConfigurationPolicyIfNeeded(
                targetURL: targetURL,
                reason: "Tab.refresh"
            )
        if protectionReloadWasRequired {
            noteProtectionManualReloadResult(
                rebuiltForConfigurationPolicy: rebuiltForConfigurationPolicy,
                targetURL: targetURL
            )
        }
        if let webView = _webView {
            if rebuiltForConfigurationPolicy {
                performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
                    on: webView,
                    waitForContentBlockingAssets: true
                ) { resolvedWebView in
                    if targetURL.isFileURL {
                        resolvedWebView.loadFileURL(
                            targetURL,
                            allowingReadAccessTo: targetURL.deletingLastPathComponent()
                        )
                    } else {
                        resolvedWebView.load(URLRequest(url: targetURL))
                    }
                }
            } else {
                performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    resolvedWebView.reload()
                }
            }
        }
        if !rebuiltForConfigurationPolicy {
            browserManager?.reloadTabAcrossWindows(id)
        }
    }

    func updateNavigationState() {
        guard !isFreezingNavigationStateDuringBackForwardGesture else { return }
        guard let webView = _webView else { return }

        let newCanGoBack = webView.canGoBack
        let newCanGoForward = webView.canGoForward

        if newCanGoBack != canGoBack || newCanGoForward != canGoForward {
            canGoBack = newCanGoBack
            canGoForward = newCanGoForward
            stateChangeEmitter.postNavigationStateDidChange(for: self)
            browserManager?.tabManager.updateTabNavigationState(self)
        }
    }

    /// Applies restored navigation state from undo/session restoration.
    func applyRestoredNavigationState() {
        guard let back = restoredCanGoBack else { return }

        if back != canGoBack {
            canGoBack = back
        }
        if let forward = restoredCanGoForward, forward != canGoForward {
            canGoForward = forward
        }

        restoredCanGoBack = nil
        restoredCanGoForward = nil
    }

    func handleSameDocumentNavigation(to newURL: URL) {
        let urlChanged = self.url.absoluteString != newURL.absoluteString
        if !urlChanged { return }

        self.url = newURL

        if urlChanged {
            applyCachedFaviconOrPlaceholder(for: newURL)
            refreshFaviconExtensionCache()
            stateChangeEmitter.postNavigationStateDidChange(for: self)
        }
    }

    func performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
        on webView: WKWebView,
        waitForContentBlockingAssets: Bool,
        performLoad: @escaping @MainActor (WKWebView) -> Void
    ) {
        guard waitForContentBlockingAssets,
              let controller = webView.configuration.userContentController.sumiNormalTabUserContentController
        else {
            performMainFrameNavigationAfterHydrationIfNeeded(
                on: webView,
                performLoad: performLoad
            )
            return
        }

        navigationTransactionOwner.performAfterPreparation(
            on: webView,
            prepare: {
                await controller.waitForContentBlockingAssetsInstalled()
            },
            performLoad: performLoad
        )
    }

    func markRegularMainFrameNavigation(on webView: WKWebView? = nil) {
        navigationTransactionOwner.markRegularMainFrameNavigation(
            on: webView,
            environment: navigationTransactionEnvironment()
        )
    }

    func beginBackForwardNavigationTracking(on webView: WKWebView) {
        navigationTransactionOwner.beginBackForwardNavigationTracking(
            on: webView,
            environment: navigationTransactionEnvironment()
        )
    }

    func finishBackForwardNavigationTracking(using webView: WKWebView?) {
        navigationTransactionOwner.finishBackForwardNavigationTracking(
            using: webView,
            environment: navigationTransactionEnvironment()
        )
    }

    func scheduleBackForwardSameDocumentSettle(using webView: WKWebView) {
        navigationTransactionOwner.scheduleBackForwardSameDocumentSettle(
            using: webView,
            environment: navigationTransactionEnvironment()
        )
    }

    private func navigationTransactionEnvironment() -> TabNavigationTransactionOwner.HistorySwipeEnvironment {
        TabNavigationTransactionOwner.HistorySwipeEnvironment(
            tabId: id,
            currentWebView: { [weak self] in
                self?._webView
            },
            currentURL: { [weak self] in
                self?.url
            },
            windowIDContaining: { [weak self] webView in
                self?.browserManager?.webViewCoordinator?.windowID(containing: webView)
            },
            beginHistorySwipeProtection: { [weak self] tabId, webView, originURL, originHistoryItem in
                self?.browserManager?.webViewCoordinator?.beginHistorySwipeProtection(
                    tabId: tabId,
                    webView: webView,
                    originURL: originURL,
                    originHistoryItem: originHistoryItem
                )
            },
            finishHistorySwipeProtection: { [weak self] tabId, webView, currentURL, currentHistoryItem in
                self?.browserManager?.webViewCoordinator?.finishHistorySwipeProtection(
                    tabId: tabId,
                    webView: webView,
                    currentURL: currentURL,
                    currentHistoryItem: currentHistoryItem
                ) ?? false
            },
            cancelWindowMutationsAfterHistorySwipe: { [weak self] windowId in
                self?.browserManager?.cancelWindowMutationsAfterHistorySwipe(in: windowId)
            },
            flushWindowMutationsAfterHistorySwipe: { [weak self] windowId in
                self?.browserManager?.flushWindowMutationsAfterHistorySwipe(in: windowId)
            },
            updateNavigationStateIfCurrentWebViewExists: { [weak self] in
                guard let self, self._webView != nil else { return }
                self.updateNavigationState()
            },
            scheduleRuntimeStatePersistence: { [weak self] in
                guard let self else { return }
                self.browserManager?.tabManager.scheduleRuntimeStatePersistence(for: self)
            },
            syncAcrossWindows: { [weak self] webView in
                guard let self else { return }
                self.browserManager?.syncTabAcrossWindows(
                    self.id,
                    originatingWebView: webView
                )
            }
        )
    }
}
