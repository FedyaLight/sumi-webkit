import Foundation
import WebKit

extension Tab {
    func unloadWebView() {
        TabWebViewCleanupOwner.unloadWebView(context: webViewCleanupContext())
    }

    /// MEMORY LEAK FIX: Comprehensive WebView cleanup to prevent memory leaks
    func cleanupCloneWebView(_ webView: WKWebView) {
        TabWebViewCleanupOwner.cleanupWebView(webView, context: webViewCleanupContext())
    }

    /// MEMORY LEAK FIX: Comprehensive cleanup for the main tab WebView
    public func performComprehensiveWebViewCleanup() {
        TabWebViewCleanupOwner.performComprehensiveCleanup(context: webViewCleanupContext())
    }

    private func webViewCleanupContext() -> TabWebViewCleanupOwner.Context {
        let browserManager = self.browserManager
        return TabWebViewCleanupOwner.Context(
            tabId: id,
            tabName: { self.name },
            handlePermissionLifecycleEvent: { event in
                browserManager?.permissionLifecycleController.handle(event)
            },
            deferProtectedWebViewCleanup: { webView, tabId, reason in
                browserManager?.webViewCoordinator?.deferProtectedWebViewCleanup(
                    webView,
                    tabID: tabId,
                    reason: reason
                ) ?? false
            },
            shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime(
                cleanupUserScripts: { controller, webViewId in
                    browserManager?.userscriptsModule.cleanupWebViewIfLoaded(
                        controller: controller,
                        webViewId: webViewId
                    )
                },
                removeWebViewFromContainers: { webView in
                    browserManager?.webViewCoordinator?.removeWebViewFromContainers(webView)
                }
            ),
            nowPlayingController: browserManager?.nativeNowPlayingController,
            currentWebView: { self.currentWebView },
            clearCurrentWebView: { self.clearCurrentWebViewOwnership() },
            removeAllWebViews: { closeActiveFullscreenMedia in
                browserManager?.webViewCoordinator?.removeAllWebViews(
                    for: self,
                    closeActiveFullscreenMedia: closeActiveFullscreenMedia
                ) ?? false
            },
            currentPermissionPageId: { self.currentPermissionPageId() },
            profilePartitionId: { self.resolveProfile()?.id.uuidString },
            invalidateCurrentPermissionPageForWebViewReplacement: { reason in
                self.invalidateCurrentPermissionPageForWebViewReplacement(reason: reason)
            },
            unbindAudioState: { webView in
                self.unbindAudioState(from: webView)
            },
            removeNavigationStateObservers: { webView in
                self.removeNavigationStateObservers(from: webView)
            },
            removeNavigationDelegateBundle: { webView in
                self.removeNavigationDelegateBundle(for: webView)
            },
            resetPlaybackActivity: {
                self.resetPlaybackActivity()
            },
            setLoadingIdle: {
                self.loadingState = .idle
            }
        )
    }
}
