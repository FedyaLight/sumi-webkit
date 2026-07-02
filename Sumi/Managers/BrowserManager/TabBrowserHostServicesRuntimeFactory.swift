import Foundation
import WebKit

@MainActor
enum TabBrowserHostServicesRuntimeFactory {
    static func webViewRoutingRuntime(
        for browserManager: BrowserManager
    ) -> TabWebViewRoutingRuntime {
        .live(webViewRoutingService: browserManager.webViewRoutingService)
    }

    static func persistenceCallbacks(
        for browserManager: BrowserManager
    ) -> TabRuntimePersistenceCallbacks {
        .live(tabManager: browserManager.tabManager)
    }

    static func mediaCallbacks(
        for browserManager: BrowserManager
    ) -> TabMediaRuntimeCallbacks {
        .live(
            nowPlayingController: browserManager.nativeNowPlayingController,
            backgroundMediaOptimizationService: browserManager.backgroundMediaOptimizationService
        )
    }

    static func scriptMessageRuntime(
        for browserManager: BrowserManager
    ) -> TabScriptMessageRuntime {
        .live(glanceManager: browserManager.glanceManager)
    }

    static func closeLifecycleRuntime(
        for browserManager: BrowserManager
    ) -> TabCloseLifecycleRuntime {
        .live(
            cleanupZoomForTab: { [weak browserManager] tabId in
                browserManager?.zoomCommandOwner.cleanupZoomForTab(tabId)
            },
            updateTabVisibility: { [weak browserManager] in
                browserManager?.compositorManager.updateTabVisibility()
            },
            removeTab: { [weak browserManager] tabId in
                browserManager?.tabManager.removeTab(tabId)
            }
        )
    }

    static func permissionRuntime(
        for browserManager: BrowserManager
    ) -> TabPermissionRuntime {
        .live(
            permissionBridges: { [weak browserManager] in
                browserManager?.permissionRuntime.permissionBridges
            },
            handlePermissionLifecycleEvent: { [weak browserManager] event in
                browserManager?.permissionRuntime.permissionLifecycleController.handle(event)
            },
            isActiveGlancePreviewSurface: { [weak browserManager] tabId, webView in
                guard let browserManager,
                      let session = browserManager.glanceManager.currentSession,
                      session.previewTab.id == tabId,
                      session.previewTab.existingWebView === webView,
                      let windowState = browserManager.windowRegistry?.windows[session.windowId],
                      browserManager.glanceManager.activeSession(for: windowState)?.id == session.id
                else {
                    return false
                }
                return true
            }
        )
    }

    static func dataServices(
        for browserManager: BrowserManager
    ) -> TabDependencyDataServices? {
        TabDependencyDataServices(
            faviconService: browserManager.dataServices.faviconService,
            faviconImageService: browserManager.dataServices.faviconImageService,
            visitedLinkStore: browserManager.dataServices.visitedLinkStore
        )
    }
}

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

@MainActor
extension TabScriptMessageRuntime {
    static func live(glanceManager: GlanceManager) -> Self {
        Self(
            presentExternalURLInGlance: { [weak glanceManager] url, tab, originRectInWindow in
                glanceManager?.presentExternalURL(
                    url,
                    from: tab,
                    originRectInWindow: originRectInWindow
                )
            }
        )
    }
}

@MainActor
extension TabCloseLifecycleRuntime {
    static func live(
        cleanupZoomForTab: @escaping (UUID) -> Void,
        updateTabVisibility: @escaping () -> Void,
        removeTab: @escaping (UUID) -> Void
    ) -> Self {
        Self(
            cleanupZoomForTab: cleanupZoomForTab,
            updateTabVisibility: updateTabVisibility,
            removeTab: removeTab
        )
    }
}

@MainActor
extension TabPermissionRuntime {
    static func live(
        permissionBridges: @escaping () -> BrowserPermissionBridgeRegistry?,
        handlePermissionLifecycleEvent: @escaping (SumiPermissionLifecycleEvent) -> Void,
        isActiveGlancePreviewSurface: @escaping (_ tabId: UUID, _ webView: WKWebView) -> Bool
    ) -> Self {
        Self(
            permissionBridges: permissionBridges,
            handlePermissionLifecycleEvent: handlePermissionLifecycleEvent,
            isActiveGlancePreviewSurface: isActiveGlancePreviewSurface
        )
    }
}
