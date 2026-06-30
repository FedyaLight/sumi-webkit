import Foundation
import WebKit

@MainActor
extension TabWebViewRoutingRuntime {
    static func live(webViewRoutingService: BrowserWebViewRoutingService) -> Self {
        Self(
            syncTabAcrossWindows: { [weak webViewRoutingService] tabId, webView in
                webViewRoutingService?.syncTabAcrossWindows(
                    tabId,
                    originatingWebView: webView
                )
            },
            reloadTabAcrossWindows: { [weak webViewRoutingService] tabId in
                webViewRoutingService?.reloadTabAcrossWindows(tabId)
            },
            setMuteState: { [weak webViewRoutingService] muted, tabId in
                webViewRoutingService?.setMuteState(muted, for: tabId)
            }
        )
    }
}

@MainActor
extension TabRuntimePersistenceCallbacks {
    static func live(tabManager: TabManager) -> Self {
        Self(
            updateNavigationState: { [weak tabManager] tab in
                tabManager?.updateTabNavigationState(tab)
            },
            scheduleRuntimeStatePersistence: { [weak tabManager] tab in
                tabManager?.scheduleRuntimeStatePersistence(for: tab)
            }
        )
    }
}

@MainActor
extension TabMediaRuntimeCallbacks {
    static func live(
        nowPlayingController: any SumiNativeNowPlayingRuntimeControlling,
        backgroundMediaOptimizationService: SumiBackgroundMediaOptimizationService
    ) -> Self {
        Self(
            scheduleNowPlayingRefresh: { [weak nowPlayingController] delayNanoseconds in
                nowPlayingController?.scheduleRefresh(delayNanoseconds: delayNanoseconds)
            },
            scheduleBackgroundMediaReconcile: { [weak backgroundMediaOptimizationService] reason in
                backgroundMediaOptimizationService?.scheduleReconcile(reason: reason)
            },
            notifyNowPlayingTabUnloaded: { [weak nowPlayingController] tabId in
                nowPlayingController?.handleTabUnloaded(tabId)
                nowPlayingController?.scheduleRefresh(delayNanoseconds: 0)
            }
        )
    }
}
