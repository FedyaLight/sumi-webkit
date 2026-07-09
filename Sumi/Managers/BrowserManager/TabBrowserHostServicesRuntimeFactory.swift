import Foundation
import WebKit
import SumiDomain

@MainActor
enum TabBrowserHostServicesRuntimeFactory {
    static func webViewRoutingRuntime(
        for browserManager: BrowserManager
    ) -> TabWebViewRoutingRuntime {
        .make(webViewRoutingService: browserManager.webViewRoutingService)
    }

    static func persistenceCallbacks(
        for browserManager: BrowserManager
    ) -> TabRuntimePersistenceCallbacks {
        .make(tabManager: browserManager.tabManager)
    }

    static func mediaCallbacks(
        for browserManager: BrowserManager
    ) -> TabMediaRuntimeCallbacks {
        .make(
            nowPlayingController: browserManager.nativeNowPlayingController,
            backgroundMediaOptimizationService: browserManager.backgroundMediaOptimizationService
        )
    }

    static func scriptMessageRuntime(
        for browserManager: BrowserManager
    ) -> TabScriptMessageRuntime {
        .make(glanceManager: browserManager.glanceManager)
    }

    static func closeLifecycleRuntime(
        for browserManager: BrowserManager
    ) -> TabCloseLifecycleRuntime {
        .make(
            cleanupZoomForTab: { [weak browserManager] tabId in
                browserManager?.chromeBundle.zoomCommandOwner.cleanupZoomForTab(tabId)
            },
            updateTabVisibility: { [weak browserManager] in
                browserManager?.compositorManager.updateTabVisibility()
            },
            removeTab: { [weak browserManager] tabId in
                browserManager?.tabManager.tabRemovalOwner.removeTab(tabId)
            }
        )
    }

    static func permissionRuntime(
        for browserManager: BrowserManager
    ) -> TabPermissionRuntime {
        .make(
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
                      browserManager.webViewRoutingService.ownsLiveWebView(
                        webView,
                        for: session.previewTab
                      ),
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
    static func make(webViewRoutingService: BrowserWebViewRoutingService) -> Self {
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
            },
            noteParkedWebView: { [weak webViewRoutingService] webView, tabId in
                webViewRoutingService?.noteParkedWebView(webView, for: tabId)
            },
            noteUntrackedWebView: { [weak webViewRoutingService] webView, tabId in
                webViewRoutingService?.noteUntrackedWebView(webView, for: tabId)
            },
            notePrimaryAssignment: { [weak webViewRoutingService] windowId, webView, tabId in
                webViewRoutingService?.notePrimaryAssignment(
                    windowId: windowId,
                    webView: webView,
                    for: tabId
                )
            },
            clearPrimaryAssignment: { [weak webViewRoutingService] tabId in
                webViewRoutingService?.clearPrimaryAssignment(for: tabId)
            },
            clearWebViewSession: { [weak webViewRoutingService] tabId in
                webViewRoutingService?.clearWebViewSession(for: tabId)
            },
            anyLiveWebView: { [weak webViewRoutingService] tab in
                webViewRoutingService?.anyLiveWebViewIfAvailable(for: tab)
            },
            sessionParkedWebView: { [weak webViewRoutingService] tabId in
                webViewRoutingService?.sessionParkedWebView(for: tabId)
            },
            sessionUntrackedWebView: { [weak webViewRoutingService] tabId in
                webViewRoutingService?.sessionUntrackedWebView(for: tabId)
            },
            sessionPrimaryWindowId: { [weak webViewRoutingService] tabId in
                webViewRoutingService?.sessionPrimaryWindowId(for: tabId)
            },
            sessionPrimaryWebView: { [weak webViewRoutingService] tabId in
                webViewRoutingService?.sessionPrimaryWebView(for: tabId)
            },
            primaryTrackedWindowId: { [weak webViewRoutingService] tabId in
                webViewRoutingService?.primaryTrackedWindowIdIfAvailable(for: tabId)
            },
            windowOwnedWebView: { [weak webViewRoutingService] tabId, windowId in
                webViewRoutingService?.webViewIfAvailable(for: tabId, in: windowId)
            },
            hasLiveWebView: { [weak webViewRoutingService] tab in
                webViewRoutingService?.hasLiveWebViewIfAvailable(for: tab) ?? false
            },
            adoptLocalWebViewSession: { [weak webViewRoutingService] session, tabId in
                webViewRoutingService?.adoptLocalWebViewSession(session, for: tabId)
            }
        )
    }
}

@MainActor
extension TabRuntimePersistenceCallbacks {
    static func make(tabManager: TabManager) -> Self {
        Self(
            updateNavigationState: { [weak tabManager] tab in
                tabManager?.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
            },
            scheduleRuntimeStatePersistence: { [weak tabManager] tab in
                tabManager?.structuralPersistence.scheduleRuntimeStatePersistence(for: tab)
            }
        )
    }
}

@MainActor
extension TabMediaRuntimeCallbacks {
    static func make(
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
    static func make(glanceManager: GlanceManager) -> Self {
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
    static func make(
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
    static func make(
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
