import Foundation
import SumiDomain
import WebKit

@MainActor
enum TabBrowserHostServicesRuntimeFactory {
    static func webViewRoutingRuntime(
        service: BrowserWebViewRoutingService
    ) -> TabWebViewRoutingRuntime {
        .make(webViewRoutingService: service)
    }

    static func persistenceCallbacks(
        persistence: TabStructuralPersistenceService,
        shortcutSessions: ShortcutLiveSessionPersistence
    ) -> TabRuntimePersistenceCallbacks {
        .make(
            persistence: persistence,
            shortcutSessions: shortcutSessions
        )
    }

    static func mediaCallbacks(
        nowPlayingController: any SumiNativeNowPlayingRuntimeControlling
    ) -> TabMediaRuntimeCallbacks {
        .make(
            nowPlayingController: nowPlayingController
        )
    }

    static func closeLifecycleRuntime(
        zoom: BrowserZoomCommandOwner,
        compositor: TabCompositorManager,
        tabClosure: TabClosureService
    ) -> TabCloseLifecycleRuntime {
        .make(
            cleanupZoomForTab: { [weak zoom] tabId in
                zoom?.cleanupZoomForTab(tabId)
            },
            updateTabVisibility: { [weak compositor] in
                compositor?.updateTabVisibility()
            },
            removeTab: { [weak tabClosure] tabId in
                tabClosure?.removeTab(tabId)
            }
        )
    }

    static func permissionRuntime(
        permissionRuntime: BrowserManagerPermissionRuntime,
        glanceManager: GlanceManager,
        routing: BrowserWebViewRoutingService,
        windowRegistry: @escaping @MainActor () -> WindowRegistry?,
        spaces: TabSpaceCollectionStateOwner,
        profiles: ProfileManager,
        auxiliaryTabs: AuxiliaryMiniWindowTabLifecycleTransaction,
        ownershipQuery: WebViewOwnershipQuery,
        visibility: WebViewVisibilityRuntime
    ) -> TabPermissionRuntime {
        .make(
            permissionBridges: { [weak permissionRuntime] in
                permissionRuntime?.permissionBridges
            },
            handlePermissionLifecycleEvent: { [weak permissionRuntime] event in
                permissionRuntime?.permissionLifecycleController.handle(event)
            },
            isActiveGlancePreviewSurface: {
                [weak glanceManager, weak routing]
                tabId,
                webView in
                guard let glanceManager,
                      let routing,
                      let session = glanceManager.currentSession,
                      session.previewTab.id == tabId,
                      routing.ownsLiveWebView(
                          webView,
                          for: session.previewTab
                      ),
                      let windowState = windowRegistry()?.windows[session.windowId],
                      glanceManager.activeSession(for: windowState)?.id
                      == session.id
                else {
                    return false
                }
                return true
            },
            surfaceState: { tabId, webView in
                guard let tracked = ownershipQuery.trackedOwner(
                          containing: webView
                      ),
                      tracked.tabID == tabId,
                      let registry = windowRegistry(),
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
            profile: { tabId, webView in
                if let tracked = ownershipQuery.trackedOwner(
                    containing: webView
                ) {
                    guard
                      tracked.tabID == tabId,
                      let sourceWindow = windowRegistry()?
                          .windows[tracked.windowID],
                      let sourceTab = (webView as? FocusableWKWebView)?.owningTab,
                      sourceTab.id == tabId
                    else { return nil }
                    if sourceWindow.isIncognito {
                        guard let profile = sourceWindow.ephemeralProfile,
                              sourceTab.profileId == nil
                                || sourceTab.profileId == profile.id
                        else {
                            return nil
                        }
                        return profile
                    }

                    if let profileID = sourceTab.profileId {
                        // Shortcuts execute in an explicit profile while
                        // remaining presented in the window's Space/profile.
                        guard let profile = profiles.profiles.first(where: {
                            $0.id == profileID
                        }),
                              webView.configuration.websiteDataStore
                                === profile.dataStore
                        else {
                            return nil
                        }
                        return profile
                    }

                    let sourceSpaceID = sourceTab.spaceId
                        ?? sourceWindow.currentSpaceId
                    let spaceProfileID = sourceSpaceID.flatMap {
                        spaces.profileId(for: $0)
                    }
                    let candidates = [
                        spaceProfileID,
                        sourceWindow.currentProfileId,
                    ].compactMap(\.self)
                    guard Set(candidates).count == 1,
                          let profileID = candidates.first,
                          let profile = profiles.profiles.first(where: {
                              $0.id == profileID
                          }),
                          webView.configuration.websiteDataStore
                            === profile.dataStore
                    else {
                        return nil
                    }
                    return profile
                }

                guard let sourceTab = (webView as? FocusableWKWebView)?
                    .owningTab,
                      sourceTab.id == tabId,
                      auxiliaryTabs.containsExact(sourceTab),
                      routing.ownsLiveWebView(
                          webView,
                          for: sourceTab
                      ),
                      let profileID = sourceTab.profileId,
                      let profile = sourceTab.resolveProfile(),
                      profile.id == profileID,
                      webView.configuration
                      .sumiIsNormalTabWebViewConfiguration == false,
                      webView.configuration.websiteDataStore
                      === profile.dataStore
                else {
                    return nil
                }
                return profile
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
            pagePresentationDidChange: {
                [weak webViewRoutingService] tabId,
                webView in
                webViewRoutingService?.pagePresentationDidChange(
                    tabId,
                    on: webView
                )
            },
            reloadTabAcrossWindows: { [weak webViewRoutingService] tabId, intent, policy in
                webViewRoutingService?.reloadTabAcrossWindows(
                    tabId,
                    intent: intent,
                    policy: policy
                ) ?? .failed(
                    intent: intent,
                    reason: .deliveryContextUnavailable
                )
            },
            reloadTabInWindow: { [weak webViewRoutingService] tabId, windowId, intent, policy in
                webViewRoutingService?.reloadTab(
                    tabId,
                    in: windowId,
                    intent: intent,
                    policy: policy
                ) ?? .failed(
                    intent: intent,
                    reason: .deliveryContextUnavailable
                )
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
    static func make(
        persistence: TabStructuralPersistenceService,
        shortcutSessions: ShortcutLiveSessionPersistence
    ) -> Self {
        Self(
            updateNavigationState: {
                [weak persistence, weak shortcutSessions] tab in
                persistence?.scheduleRuntimeStatePersistence(for: tab)
                shortcutSessions?.schedule(for: tab)
            },
            scheduleRuntimeStatePersistence: {
                [weak persistence, weak shortcutSessions] tab in
                persistence?.scheduleRuntimeStatePersistence(for: tab)
                shortcutSessions?.schedule(for: tab)
            }
        )
    }
}

@MainActor
extension TabMediaRuntimeCallbacks {
    static func make(
        nowPlayingController: any SumiNativeNowPlayingRuntimeControlling
    ) -> Self {
        Self(
            scheduleNowPlayingRefresh: { [weak nowPlayingController] delayNanoseconds in
                nowPlayingController?.scheduleRefresh(delayNanoseconds: delayNanoseconds)
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
