import Foundation
import SumiWebRuntime
import WebKit

extension DeferredWebViewCleanupExecutor {
    static func live(
        sessions: WebViewSessionRepository,
        closeWebView: @escaping CloseWebView,
        compositor: WebViewCompositorRuntime,
        trackedRegistration: WebViewTrackedRegistrationOwner,
        runtimeTabs: WebViewRuntimeTabRegistry,
        materialization: TabWebViewMaterializationService,
        processRecovery: WebContentProcessRecoveryService,
        shutdownRuntime: SumiWebViewShutdown.NormalTabRuntime,
        retireTabWebViewGeneration: @escaping RetireTabWebViewGeneration
    ) -> DeferredWebViewCleanupExecutor {
        DeferredWebViewCleanupExecutor(
            sessions: sessions,
            closeWebView: closeWebView,
            removeFromContainers: { webView in
                compositor.removeWebViewFromContainers(webView)
                return true
            },
            cleanupTrackedWebView: { webView, owner, tab in
                guard trackedRegistration.cleanupUnprotectedTrackedWebView(
                    webView,
                    owner: owner,
                    tab: tab
                ) else {
                    return false
                }
                if let tab, runtimeTabs.isRetiring(tab) == false {
                    materialization.refreshPrimary(for: tab)
                }
                return true
            },
            shutdownOwnerlessWebView: { webView, _ in
                processRecovery.cancel(webView)
                SumiWebViewShutdown.perform(
                    on: webView,
                    runtime: shutdownRuntime,
                    closeActiveMediaPresentations: SumiWebViewShutdown
                        .hasActiveMediaPresentation(on: webView)
                )
            },
            finishRetirementIfDrained: { tabID in
                _ = runtimeTabs.finishRetirementIfDrained(tabID)
            },
            retireTabWebViewGeneration: retireTabWebViewGeneration
        )
    }
}

extension DeferredWebViewWindowMaintenanceExecutor {
    static func live(
        windowCleanup: WebViewWindowCleanupOwner,
        visibility: WebViewVisibilityRuntime
    ) -> DeferredWebViewWindowMaintenanceExecutor {
        DeferredWebViewWindowMaintenanceExecutor(
            cleanupWindow: windowCleanup.cleanupWindow,
            cleanupAllWebViews: windowCleanup.cleanupAllWebViews,
            evictHiddenWebViews: { windowID, visibleTabIDs in
                visibility.evictHiddenWebViewsIfNeeded(
                    in: windowID,
                    visibleTabIDs: visibleTabIDs
                )
            },
            visibleTabIDs: visibility.visibleTabIDs
        )
    }
}

extension DeferredWebViewConfigurationExecutor {
    static func live(
        rebuild: @escaping Rebuild,
        services: DeferredWebViewServices
    ) -> DeferredWebViewConfigurationExecutor {
        DeferredWebViewConfigurationExecutor(
            rebuild: rebuild,
            assignProfile: services.executeProfileAssignment,
            assignSpaceProfile: services.executeSpaceProfileAssignment
        )
    }
}
