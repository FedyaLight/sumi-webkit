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

@MainActor
extension TabHistorySwipeRuntime {
    static func live(
        webViewCoordinator: @escaping () -> WebViewCoordinator?,
        cancelWindowMutationsAfterHistorySwipe: @escaping (UUID) -> Void,
        flushWindowMutationsAfterHistorySwipe: @escaping (UUID) -> Void
    ) -> Self {
        Self(
            windowIDContaining: { webView in
                webViewCoordinator()?.windowID(containing: webView)
            },
            beginHistorySwipeProtection: { tabId, webView, originURL, originHistoryItem in
                webViewCoordinator()?.beginHistorySwipeProtection(
                    tabId: tabId,
                    webView: webView,
                    originURL: originURL,
                    originHistoryItem: originHistoryItem
                )
            },
            finishHistorySwipeProtection: { tabId, webView, currentURL, currentHistoryItem in
                webViewCoordinator()?.finishHistorySwipeProtection(
                    tabId: tabId,
                    webView: webView,
                    currentURL: currentURL,
                    currentHistoryItem: currentHistoryItem
                ) ?? false
            },
            cancelWindowMutationsAfterHistorySwipe: cancelWindowMutationsAfterHistorySwipe,
            flushWindowMutationsAfterHistorySwipe: flushWindowMutationsAfterHistorySwipe
        )
    }
}

@MainActor
extension TabHistoryRecordingRuntime {
    static func live(
        historyManager: @escaping () -> HistoryManager?,
        currentProfileId: @escaping () -> UUID?
    ) -> Self {
        Self(
            updateTitleIfNeeded: { title, url, profileId, isEphemeral in
                historyManager()?.updateTitleIfNeeded(
                    title: title,
                    url: url,
                    profileId: profileId,
                    isEphemeral: isEphemeral
                )
            },
            addVisit: { url, title, timestamp, tabId, profileId, isEphemeral in
                historyManager()?.addVisit(
                    url: url,
                    title: title,
                    timestamp: timestamp,
                    tabId: tabId,
                    profileId: profileId,
                    isEphemeral: isEphemeral
                )
            },
            currentProfileId: currentProfileId
        )
    }
}

@MainActor
extension TabNavigationCommandRuntime {
    static func live(settings: @escaping () -> SumiSettingsService?) -> Self {
        Self(
            resolvedSearchEngineTemplate: {
                settings()?.resolvedSearchEngineTemplate
            }
        )
    }
}

@MainActor
extension TabProfileResolutionRuntime {
    static func live(browserManager: BrowserManager) -> Self {
        Self(
            ephemeralProfileForTab: { [weak browserManager] tabId, profileId in
                browserManager?.windowRegistry?.windows.values.first(where: { window in
                    window.ephemeralTabs.contains(where: { $0.id == tabId })
                })?.ephemeralProfile.flatMap { profile in
                    profile.id == profileId ? profile : nil
                }
            },
            profile: { [weak browserManager] profileId in
                browserManager?.profileManager.profiles.first { $0.id == profileId }
            },
            spaceProfile: { [weak browserManager] spaceId in
                guard let browserManager,
                      let space = browserManager.tabManager.spaces.first(where: { $0.id == spaceId }),
                      let profileId = space.profileId
                else {
                    return nil
                }
                return browserManager.profileManager.profiles.first { $0.id == profileId }
            },
            currentProfile: { [weak browserManager] in
                browserManager?.currentProfile
            },
            firstProfile: { [weak browserManager] in
                browserManager?.profileManager.profiles.first
            }
        )
    }
}
