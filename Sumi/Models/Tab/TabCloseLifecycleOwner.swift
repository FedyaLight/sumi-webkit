import Foundation
import WebKit

@MainActor
final class TabCloseLifecycleOwner {
    struct Context {
        let tabId: UUID
        let tabName: () -> String
        let cleanupNormalTabPermissionRuntime: (_ reason: String) -> Void
        let performComprehensiveWebViewCleanup: () -> Void
        let resetPlaybackActivity: () -> Void
        let applyAudioState: (SumiWebViewAudioState) -> Void
        let setLoadingIdle: () -> Void
        let cleanupZoomForTab: (UUID) -> Void
        let updateTabVisibility: () -> Void
        let currentWebView: () -> WKWebView?
        let removeNavigationStateObservers: (WKWebView) -> Void
        let removeTab: (UUID) -> Void
        let cancelProfileAwait: () -> Void
        let cancelPendingMainFrameNavigation: () -> Void
    }

    func close(context: Context) {
        RuntimeDiagnostics.emit("Closing tab: \(context.tabName())")

        context.cleanupNormalTabPermissionRuntime("normal-tab-close")
        context.performComprehensiveWebViewCleanup()

        context.resetPlaybackActivity()
        context.applyAudioState(.unmuted(isPlayingAudio: false))
        context.setLoadingIdle()

        context.cleanupZoomForTab(context.tabId)
        context.updateTabVisibility()

        if let webView = context.currentWebView() {
            context.removeNavigationStateObservers(webView)
        }

        context.removeTab(context.tabId)
        context.cancelProfileAwait()
        context.cancelPendingMainFrameNavigation()

        RuntimeDiagnostics.debug("Tab close completed.", category: "Tab")
    }
}

extension TabCloseLifecycleOwner.Context {
    @MainActor
    static func live(tab: Tab) -> Self {
        Self(
            tabId: tab.id,
            tabName: { tab.name },
            cleanupNormalTabPermissionRuntime: { reason in
                tab.cleanupNormalTabPermissionRuntime(reason: reason)
            },
            performComprehensiveWebViewCleanup: {
                tab.performComprehensiveWebViewCleanup()
            },
            resetPlaybackActivity: {
                tab.resetPlaybackActivity()
            },
            applyAudioState: { state in
                tab.applyAudioState(state)
            },
            setLoadingIdle: {
                tab.loadingState = .idle
            },
            cleanupZoomForTab: { tabId in
                tab.closeLifecycleRuntime.cleanupZoomForTab(tabId)
            },
            updateTabVisibility: {
                tab.closeLifecycleRuntime.updateTabVisibility()
            },
            currentWebView: {
                tab.currentWebView
            },
            removeNavigationStateObservers: { webView in
                tab.removeNavigationStateObservers(from: webView)
            },
            removeTab: { tabId in
                tab.closeLifecycleRuntime.removeTab(tabId)
            },
            cancelProfileAwait: {
                tab.profileAwaitCancellable?.cancel()
                tab.profileAwaitCancellable = nil
            },
            cancelPendingMainFrameNavigation: {
                tab.cancelPendingMainFrameNavigation()
            }
        )
    }
}
