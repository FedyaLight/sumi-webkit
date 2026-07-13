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
                browserManager?.tabManager.tabClosureService.removeTab(tabId)
            }
        )
    }

    static func permissionRuntime(
        for browserManager: BrowserManager,
        ownershipQuery: WebViewOwnershipQuery,
        visibility: WebViewVisibilityRuntime
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
            },
            surfaceState: { [weak browserManager] tabId, webView in
                guard let browserManager,
                      let tracked = ownershipQuery.trackedOwner(
                          containing: webView
                      ),
                      tracked.tabID == tabId,
                      let registry = browserManager.windowRegistry,
                      registry.windows[tracked.windowID] != nil
                else {
                    return .inactive
                }
                let isVisible = visibility
                    .visibleTabIDs(in: tracked.windowID)
                    .contains(tabId)
                return TabPermissionSurfaceState(
                    isActive: isVisible
                        && registry.activeWindowId == tracked.windowID,
                    isVisible: isVisible
                )
            },
            profile: { [weak browserManager] tabId, webView in
                guard let browserManager,
                      let tracked = ownershipQuery.trackedOwner(
                          containing: webView
                      ),
                      tracked.tabID == tabId,
                      let sourceWindow = browserManager.windowRegistry?
                          .windows[tracked.windowID],
                      let sourceTab = (webView as? FocusableWKWebView)?.owningTab,
                      sourceTab.id == tabId
                else {
                    return nil
                }
                if sourceWindow.isIncognito {
                    guard let profile = sourceWindow.ephemeralProfile,
                          sourceTab.profileId == nil
                            || sourceTab.profileId == profile.id
                    else {
                        return nil
                    }
                    return profile
                }

                let sourceSpaceID = sourceTab.spaceId
                    ?? sourceWindow.currentSpaceId
                let spaceProfileID = sourceSpaceID.flatMap {
                    browserManager.tabManager.spaceStateOwner.profileId(for: $0)
                }
                let candidates = [
                    sourceTab.profileId,
                    spaceProfileID,
                    sourceWindow.currentProfileId,
                ].compactMap(\.self)
                guard Set(candidates).count == 1,
                      let profileID = candidates.first
                else {
                    return nil
                }
                return browserManager.profileManager.profiles.first {
                    $0.id == profileID
                }
            }
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
            reloadTabAcrossWindows: { [weak webViewRoutingService] tabId, intent, policy in
                webViewRoutingService?.reloadTabAcrossWindows(
                    tabId,
                    intent: intent,
                    policy: policy
                )
            },
            reloadTabInWindow: { [weak webViewRoutingService] tabId, windowId, intent, policy in
                webViewRoutingService?.reloadTab(
                    tabId,
                    in: windowId,
                    intent: intent,
                    policy: policy
                ) ?? .failed
            },
            retainWebContentProcessRecovery: { [weak webViewRoutingService] tabId, webView in
                webViewRoutingService?.retainWebContentProcessRecovery(
                    tabId,
                    on: webView
                ) ?? false
            },
            recoverWebContentProcess: { [weak webViewRoutingService] tabId, webView in
                webViewRoutingService?.recoverWebContentProcess(
                    tabId,
                    on: webView
                ) ?? .failed
            },
            cancelWebContentProcessRecovery: { [weak webViewRoutingService] webView in
                webViewRoutingService?.cancelWebContentProcessRecovery(
                    on: webView
                )
            },
            setMuteState: { [weak webViewRoutingService] muted, tabId in
                webViewRoutingService?.setMuteState(muted, for: tabId)
            },
            bindWebViewSession: { [weak webViewRoutingService] handle in
                webViewRoutingService?.bindWebViewSession(handle)
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
            invalidateBackgroundMediaCommand: { [weak backgroundMediaOptimizationService] webView in
                backgroundMediaOptimizationService?.invalidateAppliedCommand(for: webView)
            },
            notifyNowPlayingTabUnloaded: { [weak nowPlayingController] tabId in
                nowPlayingController?.handleTabUnloaded(tabId)
                nowPlayingController?.scheduleRefresh(delayNanoseconds: 0)
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
        isActiveGlancePreviewSurface: @escaping (_ tabId: UUID, _ webView: WKWebView) -> Bool,
        surfaceState: @escaping (
            _ tabId: UUID,
            _ webView: WKWebView
        ) -> TabPermissionSurfaceState,
        profile: @escaping (
            _ tabId: UUID,
            _ webView: WKWebView
        ) -> Profile?
    ) -> Self {
        Self(
            permissionBridges: permissionBridges,
            handlePermissionLifecycleEvent: handlePermissionLifecycleEvent,
            isActiveGlancePreviewSurface: isActiveGlancePreviewSurface,
            surfaceState: surfaceState,
            profile: profile
        )
    }
}
