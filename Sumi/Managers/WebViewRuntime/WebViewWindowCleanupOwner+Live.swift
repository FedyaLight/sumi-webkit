import Foundation
import SumiWebRuntime

extension WebViewWindowCleanupOwner {
    static func live(
        cleanupScope: WebViewCleanupScopeOwner,
        sessions: WebViewSessionRepository,
        visibleRuntime: VisibleWebViewRuntimeOwner,
        mediaProtection: WebViewMediaProtectionOwner,
        runtimeTabs: WebViewRuntimeTabRegistry,
        resolveRuntimeTab: @escaping WebViewRuntimeTabRegistry.RuntimeTabResolver,
        commandAdmission: DeferredProtectedCommandAdmissionService,
        trackedRegistration: WebViewTrackedRegistrationOwner,
        materialization: TabWebViewMaterializationService,
        compositor: WebViewCompositorRuntime,
        flushDeferredCommands: @escaping @MainActor (ObjectIdentifier) -> Void,
        websiteDataCleanup: WebsiteDataCleanupService
    ) -> WebViewWindowCleanupOwner {
        WebViewWindowCleanupOwner(
            cleanupScopeOwner: cleanupScope,
            webViewSessions: sessions,
            visibleWebViewRuntimeOwner: visibleRuntime,
            mediaProtectionOwner: mediaProtection,
            tabForID: { tabID in
                runtimeTabs.tabForCleanup(
                    tabID,
                    resolveRuntimeTab: resolveRuntimeTab
                )
            },
            isWebViewProtectedFromCompositorMutation: mediaProtection.isProtected,
            enqueueDeferredProtectedCommand: { command, webView, reason in
                commandAdmission.schedule(
                    command,
                    for: webView,
                    reason: reason
                ).wasScheduled
            },
            cleanupUnprotectedTrackedWebView: { webView, owner, tabHandle in
                let tab = tabHandle.flatMap { handle in
                    runtimeTabs.tabForCleanup(
                        handle.id,
                        resolveRuntimeTab: resolveRuntimeTab
                    ).flatMap { $0 === handle ? $0 : nil }
                }
                return trackedRegistration.cleanupUnprotectedTrackedWebView(
                    webView,
                    owner: owner,
                    tab: tab
                )
            },
            refreshPrimaryTrackedWebView: { tabHandle in
                guard let tab = runtimeTabs.tabForCleanup(
                    tabHandle.id,
                    resolveRuntimeTab: resolveRuntimeTab
                ), tab === tabHandle else {
                    return
                }
                materialization.refreshPrimary(for: tab)
            },
            removeCompositorContainerView: compositor.removeContainer,
            flushDeferredProtectedCommands: flushDeferredCommands,
            finishCleanupSuppression: websiteDataCleanup.webViewsDidLeaveRuntime
        )
    }
}
