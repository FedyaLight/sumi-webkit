import Foundation
import WebKit

extension Tab {
    // MARK: - Navigation Controls

    func goBack() {
        guard canGoBack else { return }
        guard let webView = currentWebView else { return }
        SumiWebViewNavigator.goBack(on: webView)
    }

    func goForward() {
        guard canGoForward else { return }
        guard let webView = currentWebView else { return }
        SumiWebViewNavigator.goForward(on: webView)
    }

    func stopLoading(on webView: WKWebView? = nil) {
        let resolvedWebView = webView ?? currentWebView
        resolvedWebView?.stopLoading()

        if loadingState.isLoading {
            loadingState = .idle
        }
    }

    func refresh() {
        navigationCommandOwner.refresh(self)
    }

    func updateNavigationState() {
        guard !navigationRuntime.navigationTransactionOwner.isFreezingNavDuringBackForwardGesture else { return }
        guard let webView = currentWebView else { return }

        let newCanGoBack = webView.canGoBack
        let newCanGoForward = webView.canGoForward

        if newCanGoBack != canGoBack || newCanGoForward != canGoForward {
            canGoBack = newCanGoBack
            canGoForward = newCanGoForward
            stateChangeEmitter.postNavigationStateDidChange(for: self)
            navigationRuntime.persistenceCallbacks.updateNavigationState(self)
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

    /// Reflects restored back/forward availability in presentation state
    /// immediately, without consuming the restored values. Needed because web
    /// view materialization can be deferred (e.g. startup protection), and the
    /// UI should not show a restored tab as having no history until then.
    func applyRestoredNavigationPresentation() {
        if let back = restoredCanGoBack, back != canGoBack {
            canGoBack = back
        }
        if let forward = restoredCanGoForward, forward != canGoForward {
            canGoForward = forward
        }
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
        navigationCommandOwner.performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
            on: webView,
            tab: self,
            waitForContentBlockingAssets: waitForContentBlockingAssets,
            performLoad: performLoad
        )
    }

    func markRegularMainFrameNavigation(on webView: WKWebView? = nil) {
        navigationRuntime.navigationTransactionOwner.markRegularMainFrameNavigation(
            on: webView,
            environment: navigationTransactionEnvironment()
        )
    }

    func beginBackForwardNavigationTracking(on webView: WKWebView) {
        navigationRuntime.navigationTransactionOwner.beginBackForwardNavigationTracking(
            on: webView,
            environment: navigationTransactionEnvironment()
        )
    }

    func finishBackForwardNavigationTracking(using webView: WKWebView?) {
        navigationRuntime.navigationTransactionOwner.finishBackForwardNavigationTracking(
            using: webView,
            environment: navigationTransactionEnvironment()
        )
    }

    func scheduleBackForwardSameDocumentSettle(using webView: WKWebView) {
        navigationRuntime.navigationTransactionOwner.scheduleBackForwardSameDocumentSettle(
            using: webView,
            environment: navigationTransactionEnvironment()
        )
    }

    private func navigationTransactionEnvironment() -> TabNavigationTransactionOwner.HistorySwipeEnvironment {
        TabNavigationTransactionOwner.HistorySwipeEnvironment(
            tabId: id,
            currentWebView: { [weak self] in
                self?.currentWebView
            },
            currentURL: { [weak self] in
                self?.url
            },
            windowIDContaining: { [weak self] webView in
                self?.navigationRuntime.historySwipeRuntime.windowIDContaining(webView)
            },
            beginHistorySwipeProtection: { [weak self] tabId, webView, originURL, originHistoryItem in
                self?.navigationRuntime.historySwipeRuntime.beginHistorySwipeProtection(
                    tabId,
                    webView,
                    originURL,
                    originHistoryItem
                )
            },
            finishHistorySwipeProtection: { [weak self] tabId, webView, currentURL, currentHistoryItem in
                self?.navigationRuntime.historySwipeRuntime.finishHistorySwipeProtection(
                    tabId,
                    webView,
                    currentURL,
                    currentHistoryItem
                ) ?? false
            },
            cancelWindowMutationsAfterHistorySwipe: { [weak self] windowId in
                self?.navigationRuntime.historySwipeRuntime.cancelWindowMutationsAfterHistorySwipe(windowId)
            },
            flushWindowMutationsAfterHistorySwipe: { [weak self] windowId in
                self?.navigationRuntime.historySwipeRuntime.flushWindowMutationsAfterHistorySwipe(windowId)
            },
            updateNavStateIfCurrentWebViewExists: { [weak self] in
                guard let self, self.hasCurrentWebView else { return }
                self.updateNavigationState()
            },
            scheduleRuntimeStatePersistence: { [weak self] in
                guard let self else { return }
                self.navigationRuntime.persistenceCallbacks.scheduleRuntimeStatePersistence(self)
            },
            syncAcrossWindows: { [weak self] webView in
                guard let self else { return }
                self.navigationRuntime.webViewRouting.syncTabAcrossWindows(
                    self.id,
                    webView
                )
            }
        )
    }
}
