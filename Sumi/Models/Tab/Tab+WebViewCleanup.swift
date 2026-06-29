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
        TabWebViewCleanupOwner.Context(
            tabId: id,
            tabName: { self.name },
            browserManager: browserManager,
            nowPlayingController: browserManager?.nativeNowPlayingController,
            currentWebView: { self._webView },
            clearCurrentWebView: { self.clearCurrentWebViewOwnership() },
            removeAllWebViews: { closeActiveFullscreenMedia in
                self.browserManager?.webViewCoordinator?.removeAllWebViews(
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
