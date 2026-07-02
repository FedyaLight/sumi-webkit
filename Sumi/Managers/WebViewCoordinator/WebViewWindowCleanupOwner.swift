import Foundation
import WebKit

/// Owns window-scoped and app-wide cleanup of tracked WebViews, including the
/// registry/bookkeeping reset once every WebView is released.
@MainActor
final class WebViewWindowCleanupOwner {
    struct Dependencies {
        let cleanupScopeOwner: WebViewCleanupScopeOwner
        let webViewRegistry: WindowWebViewRegistry
        let visibleWebViewRuntimeOwner: VisibleWebViewRuntimeOwner
        let mediaProtectionOwner: WebViewMediaProtectionOwner
        let browserRuntimeContext: @MainActor () -> WebViewCoordinatorBrowserRuntimeContext?
        let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
        let enqueueDeferredProtectedCommand:
            @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool
        let cleanupUnprotectedTrackedWebView:
            @MainActor (WKWebView, TrackedWebViewOwner, Tab?) -> Void
        let refreshPrimaryTrackedWebView: @MainActor (Tab) -> Void
        let removeCompositorContainerView: @MainActor (UUID) -> Void
        let finishCleanupSuppression: @MainActor ([ObjectIdentifier]) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func cleanupWindow(_ windowId: UUID, tabManager: TabManager) {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.cleanupWindow")
        defer {
            PerformanceTrace.endInterval("WebViewCoordinator.cleanupWindow", signpostState)
        }

        dependencies.visibleWebViewRuntimeOwner.cancelScheduledPreparation(for: windowId)
        dependencies.cleanupScopeOwner.cleanupWindow(
            windowId,
            entries: dependencies.webViewRegistry.trackedWebViews(in: windowId),
            runtime: scopeRuntime(tabManager: tabManager)
        )
        dependencies.removeCompositorContainerView(windowId)
    }

    func cleanupAllWebViews(tabManager: TabManager) {
        dependencies.cleanupScopeOwner.cleanupAllWebViews(
            entries: dependencies.webViewRegistry.trackedWebViews(),
            totalWebViewCount: dependencies.webViewRegistry.totalTrackedWebViewCount,
            runtime: scopeRuntime(tabManager: tabManager)
        )

        if dependencies.webViewRegistry.isEmpty {
            dependencies.webViewRegistry.removeAll()
            dependencies.visibleWebViewRuntimeOwner.resetWindowRegistrations()
            dependencies.mediaProtectionOwner.removeVisualHandoffFullscreenAndNowPlayingState()
        }

        RuntimeDiagnostics.debug("Completed full WebView cleanup.", category: "WebViewCoordinator")

        dependencies.finishCleanupSuppression(
            dependencies.mediaProtectionOwner.pruneStaleBookkeeping(reason: "cleanupAllWebViews")
        )
    }

    private func scopeRuntime(tabManager: TabManager) -> WebViewCleanupScopeOwner.Runtime {
        let runtimeContext = dependencies.browserRuntimeContext()
        return WebViewCleanupScopeOwner.Runtime(
            tabForID: { tabID in
                runtimeContext?.tab(tabID) ?? tabManager.tab(for: tabID)
            },
            isWebViewProtectedFromCompositorMutation: { [dependencies] webView in
                dependencies.isWebViewProtectedFromCompositorMutation(webView)
            },
            enqueueDeferredProtectedCommand: { [dependencies] command, webView, reason in
                dependencies.enqueueDeferredProtectedCommand(command, webView, reason)
            },
            cleanupUnprotectedTrackedWebView: { [dependencies] webView, owner, tab in
                dependencies.cleanupUnprotectedTrackedWebView(webView, owner, tab)
            },
            refreshPrimaryTrackedWebView: { [dependencies] tab in
                dependencies.refreshPrimaryTrackedWebView(tab)
            }
        )
    }
}

extension WebViewWindowCleanupOwner.Dependencies {
    @MainActor
    static func live(coordinator: WebViewCoordinator) -> Self {
        Self(
            cleanupScopeOwner: coordinator.cleanupScopeOwner,
            webViewRegistry: coordinator.webViewRegistry,
            visibleWebViewRuntimeOwner: coordinator.visibleWebViewRuntimeOwner,
            mediaProtectionOwner: coordinator.mediaProtectionOwner,
            browserRuntimeContext: { [weak coordinator] in
                coordinator?.runtimeContextStore.browser
            },
            isWebViewProtectedFromCompositorMutation: { [weak coordinator] webView in
                coordinator?.isWebViewProtectedFromCompositorMutation(webView) ?? false
            },
            enqueueDeferredProtectedCommand: { [weak coordinator] command, webView, reason in
                coordinator?.enqueueDeferredProtectedCommand(
                    command,
                    for: webView,
                    reason: reason
                ) ?? false
            },
            cleanupUnprotectedTrackedWebView: { [weak coordinator] webView, owner, tab in
                coordinator?.cleanupUnprotectedTrackedWebView(
                    webView,
                    owner: owner,
                    tab: tab
                )
            },
            refreshPrimaryTrackedWebView: { [weak coordinator] tab in
                coordinator?.refreshPrimaryTrackedWebView(for: tab)
            },
            removeCompositorContainerView: { [weak coordinator] windowId in
                coordinator?.removeCompositorContainerView(for: windowId)
            },
            finishCleanupSuppression: { [weak coordinator] webViewIDs in
                coordinator?.finishDestructiveCleanupSuppression(for: webViewIDs)
            }
        )
    }
}
