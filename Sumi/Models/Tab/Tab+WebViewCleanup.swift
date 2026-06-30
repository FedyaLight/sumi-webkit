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
        let cleanupRuntime = webViewCleanupRuntime
        return TabWebViewCleanupOwner.Context(
            tabId: id,
            tabName: { self.name },
            handlePermissionLifecycleEvent: { [weak self] event in
                self?.permissionRuntime.handlePermissionLifecycleEvent(event)
            },
            deferProtectedWebViewCleanup: cleanupRuntime.deferProtectedWebViewCleanup,
            shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime(
                cleanupUserScripts: cleanupRuntime.cleanupUserScripts,
                removeWebViewFromContainers: cleanupRuntime.removeWebViewFromContainers
            ),
            notifyNowPlayingTabUnloaded: { tabId in
                self.mediaRuntimeCallbacks.notifyNowPlayingTabUnloaded(tabId)
            },
            currentWebView: { self.currentWebView },
            clearCurrentWebView: { self.clearCurrentWebViewOwnership() },
            removeAllWebViews: { closeActiveFullscreenMedia in
                cleanupRuntime.removeAllWebViews(self, closeActiveFullscreenMedia)
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
