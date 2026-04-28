import BrowserServicesKit
import Foundation
import WebKit

extension Tab {
    // MARK: - Navigation Controls

    func goBack() {
        guard canGoBack else { return }
        _webView?.goBack()
    }

    func goForward() {
        guard canGoForward else { return }
        _webView?.goForward()
    }

    func refresh() {
        loadingState = .didStartProvisionalNavigation
        let targetURL = _webView?.url ?? url
        let rebuiltWebView = rebuildNormalWebViewForTrackingProtectionIfNeeded(
            targetURL: targetURL,
            reason: "Tab.refresh.trackingProtectionPolicy"
        )
        let rebuiltForConfigurationPolicy = rebuiltWebView
            || rebuildNormalWebViewForAutoplayIfNeeded(
                targetURL: targetURL,
                reason: "Tab.refresh.autoplayPolicy"
            )
        if let webView = _webView
        {
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
                if #available(macOS 15.5, *) {
                    performMainFrameNavigationAfterHydrationIfNeeded(
                        on: webView
                    ) { resolvedWebView in
                        resolvedWebView.reload()
                    }
                } else {
                    performMainFrameNavigation(
                        on: webView
                    ) { resolvedWebView in
                        resolvedWebView.reload()
                    }
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
            NotificationCenter.default.post(
                name: .sumiTabNavigationStateDidChange,
                object: self,
                userInfo: ["tabId": id]
            )
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
            faviconsTabExtension?.loadCachedFavicon(previousURL: nil, error: nil)
            NotificationCenter.default.post(
                name: .sumiTabNavigationStateDidChange,
                object: self,
                userInfo: ["tabId": id]
            )
        }
    }

    func performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
        on webView: WKWebView,
        waitForContentBlockingAssets: Bool,
        performLoad: @escaping @MainActor (WKWebView) -> Void
    ) {
        guard waitForContentBlockingAssets,
              let controller = webView.configuration.userContentController as? UserContentController
        else {
            if #available(macOS 15.5, *) {
                performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView,
                    performLoad: performLoad
                )
            } else {
                performMainFrameNavigation(
                    on: webView,
                    performLoad: performLoad
                )
            }
            return
        }

        cancelPendingMainFrameNavigation()
        let token = UUID()
        pendingMainFrameNavigationToken = token
        pendingMainFrameNavigationTask = Task { @MainActor [weak self, weak webView] in
            await controller.awaitContentBlockingAssetsInstalled()
            guard let self,
                  let webView,
                  self.pendingMainFrameNavigationToken == token
            else { return }

            performLoad(webView)
            self.pendingMainFrameNavigationTask = nil
            self.pendingMainFrameNavigationToken = nil
        }
    }

    func markRegularMainFrameNavigation(on webView: WKWebView? = nil) {
        let wasFreezingNavigationState = isFreezingNavigationStateDuringBackForwardGesture
        let protectedWebView = webView ?? _webView
        let settledWindowId = protectedWebView.flatMap {
            browserManager?.webViewCoordinator?.windowID(containing: $0)
        }
        pendingBackForwardSettleTask?.cancel()
        pendingBackForwardSettleTask = nil
        pendingMainFrameNavigationKind = .load
        pendingBackForwardNavigationContext = nil
        isFreezingNavigationStateDuringBackForwardGesture = false

        if wasFreezingNavigationState {
            let wasCancelled = browserManager?.webViewCoordinator?.finishHistorySwipeProtection(
                tabId: id,
                webView: protectedWebView,
                currentURL: protectedWebView?.url,
                currentHistoryItem: protectedWebView?.backForwardList.currentItem
            ) ?? false

            if let settledWindowId {
                if wasCancelled {
                    browserManager?.cancelWindowMutationsAfterHistorySwipe(in: settledWindowId)
                } else {
                    browserManager?.flushWindowMutationsAfterHistorySwipe(in: settledWindowId)
                }
            }
        }

        if wasFreezingNavigationState, _webView != nil {
            updateNavigationState()
        }
    }

    func beginBackForwardNavigationTracking(on webView: WKWebView) {
        pendingBackForwardSettleTask?.cancel()
        pendingMainFrameNavigationKind = .backForward
        let originURL = webView.url ?? url
        let originHistoryItem = webView.backForwardList.currentItem
        pendingBackForwardNavigationContext = TabBackForwardNavigationContext(
            originURL: originURL,
            originHistoryURL: originHistoryItem?.url,
            originHistoryItem: originHistoryItem
        )
        isFreezingNavigationStateDuringBackForwardGesture = true
        browserManager?.webViewCoordinator?.beginHistorySwipeProtection(
            tabId: id,
            webView: webView,
            originURL: originURL,
            originHistoryItem: originHistoryItem
        )
        pendingBackForwardSettleTask = Task { @MainActor [weak self, weak webView] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 2_000_000_000)
            guard !Task.isCancelled else { return }
            guard self.pendingMainFrameNavigationKind == .backForward else { return }

            self.finishBackForwardNavigationTracking(using: webView)
        }
    }

    func finishBackForwardNavigationTracking(using webView: WKWebView?) {
        let wasFreezingNavigationState = isFreezingNavigationStateDuringBackForwardGesture
        let resolvedWebView = webView ?? _webView
        let settledWindowId = resolvedWebView.flatMap {
            browserManager?.webViewCoordinator?.windowID(containing: $0)
        }
        pendingBackForwardSettleTask?.cancel()
        pendingBackForwardSettleTask = nil
        pendingMainFrameNavigationKind = nil
        pendingBackForwardNavigationContext = nil
        isFreezingNavigationStateDuringBackForwardGesture = false

        let wasCancelled = browserManager?.webViewCoordinator?.finishHistorySwipeProtection(
            tabId: id,
            webView: resolvedWebView,
            currentURL: resolvedWebView?.url,
            currentHistoryItem: resolvedWebView?.backForwardList.currentItem
        ) ?? false

        if let settledWindowId {
            if wasCancelled {
                browserManager?.cancelWindowMutationsAfterHistorySwipe(in: settledWindowId)
            } else {
                browserManager?.flushWindowMutationsAfterHistorySwipe(in: settledWindowId)
            }
        }

        if wasFreezingNavigationState, _webView != nil {
            updateNavigationState()
        }
    }

    func scheduleBackForwardSameDocumentSettle(using webView: WKWebView) {
        guard pendingMainFrameNavigationKind == .backForward,
              let context = pendingBackForwardNavigationContext
        else {
            return
        }

        pendingBackForwardSettleTask?.cancel()
        pendingBackForwardSettleTask = Task { @MainActor [weak self, weak webView] in
            guard let self else { return }

            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }

            guard let webView else {
                self.finishBackForwardNavigationTracking(using: nil)
                return
            }

            if BackForwardNavigationSettleDecision.shouldApplyDeferredActions(
                originURL: context.originURL,
                originHistoryURL: context.originHistoryURL,
                originHistoryItem: context.originHistoryItem,
                currentURL: webView.url,
                currentHistoryURL: webView.backForwardList.currentItem?.url,
                currentHistoryItem: webView.backForwardList.currentItem
            ) {
                self.finishBackForwardNavigationTracking(using: webView)
                browserManager?.tabManager.scheduleRuntimeStatePersistence(for: self)
                browserManager?.syncTabAcrossWindows(
                    self.id,
                    originatingWebView: webView
                )
            } else {
                self.finishBackForwardNavigationTracking(using: webView)
            }
        }
    }
}
