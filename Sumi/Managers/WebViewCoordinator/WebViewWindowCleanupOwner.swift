import Foundation
import WebKit
import SumiWebRuntime

/// Owns window-scoped and app-wide cleanup of tracked WebViews, including the
/// registry/bookkeeping reset once every WebView is released.
@MainActor
final class WebViewWindowCleanupOwner {
    private let cleanupScopeOwner: WebViewCleanupScopeOwner
    private let webViewRegistry: WindowWebViewRegistry
    private let visibleWebViewRuntimeOwner: VisibleWebViewRuntimeOwner
    private let mediaProtectionOwner: WebViewMediaProtectionOwner
    private let browserRuntimeContext: @MainActor () -> WebViewCoordinatorBrowserRuntimeContext?
    private let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
    private let enqueueDeferredProtectedCommand:
        @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool
    private let cleanupUnprotectedTrackedWebView:
        @MainActor (WKWebView, TrackedWebViewOwner, Tab?) -> Void
    private let refreshPrimaryTrackedWebView: @MainActor (Tab) -> Void
    private let removeCompositorContainerView: @MainActor (UUID) -> Void
    private let finishCleanupSuppression: @MainActor ([ObjectIdentifier]) -> Void

    init(
        cleanupScopeOwner: WebViewCleanupScopeOwner,
        webViewRegistry: WindowWebViewRegistry,
        visibleWebViewRuntimeOwner: VisibleWebViewRuntimeOwner,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        browserRuntimeContext: @escaping @MainActor () -> WebViewCoordinatorBrowserRuntimeContext?,
        isWebViewProtectedFromCompositorMutation: @escaping @MainActor (WKWebView) -> Bool,
        enqueueDeferredProtectedCommand:
            @escaping @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool,
        cleanupUnprotectedTrackedWebView:
            @escaping @MainActor (WKWebView, TrackedWebViewOwner, Tab?) -> Void,
        refreshPrimaryTrackedWebView: @escaping @MainActor (Tab) -> Void,
        removeCompositorContainerView: @escaping @MainActor (UUID) -> Void,
        finishCleanupSuppression: @escaping @MainActor ([ObjectIdentifier]) -> Void
    ) {
        self.cleanupScopeOwner = cleanupScopeOwner
        self.webViewRegistry = webViewRegistry
        self.visibleWebViewRuntimeOwner = visibleWebViewRuntimeOwner
        self.mediaProtectionOwner = mediaProtectionOwner
        self.browserRuntimeContext = browserRuntimeContext
        self.isWebViewProtectedFromCompositorMutation = isWebViewProtectedFromCompositorMutation
        self.enqueueDeferredProtectedCommand = enqueueDeferredProtectedCommand
        self.cleanupUnprotectedTrackedWebView = cleanupUnprotectedTrackedWebView
        self.refreshPrimaryTrackedWebView = refreshPrimaryTrackedWebView
        self.removeCompositorContainerView = removeCompositorContainerView
        self.finishCleanupSuppression = finishCleanupSuppression
    }

    func cleanupWindow(_ windowId: UUID, tabManager: TabManager) {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.cleanupWindow")
        defer {
            PerformanceTrace.endInterval("WebViewCoordinator.cleanupWindow", signpostState)
        }

        visibleWebViewRuntimeOwner.cancelScheduledPreparation(for: windowId)
        cleanupScopeOwner.cleanupWindow(
            windowId,
            entries: webViewRegistry.trackedWebViews(in: windowId),
            runtime: scopeRuntime(tabManager: tabManager)
        )
        removeCompositorContainerView(windowId)
    }

    func cleanupAllWebViews(tabManager: TabManager) {
        cleanupScopeOwner.cleanupAllWebViews(
            entries: webViewRegistry.trackedWebViews(),
            totalWebViewCount: webViewRegistry.totalTrackedWebViewCount,
            runtime: scopeRuntime(tabManager: tabManager)
        )

        if webViewRegistry.isEmpty {
            webViewRegistry.removeAll()
            visibleWebViewRuntimeOwner.resetWindowRegistrations()
            mediaProtectionOwner.removeVisualHandoffFullscreenAndNowPlayingState()
        }

        RuntimeDiagnostics.debug("Completed full WebView cleanup.", category: "WebViewCoordinator")

        finishCleanupSuppression(
            mediaProtectionOwner.pruneStaleBookkeeping(reason: "cleanupAllWebViews")
        )
    }

    private func scopeRuntime(tabManager: TabManager) -> WebViewCleanupScopeOwner.Runtime {
        let runtimeContext = browserRuntimeContext()
        return WebViewCleanupScopeOwner.Runtime(
            tabForID: { tabID in
                runtimeContext?.tab(tabID) ?? tabManager.tabCollectionMembershipOwner.tab(for: tabID)
            },
            isWebViewProtectedFromCompositorMutation: { [isWebViewProtectedFromCompositorMutation] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            enqueueDeferredProtectedCommand: { [enqueueDeferredProtectedCommand] command, webView, reason in
                enqueueDeferredProtectedCommand(command, webView, reason)
            },
            cleanupUnprotectedTrackedWebView: { [cleanupUnprotectedTrackedWebView] webView, owner, tab in
                cleanupUnprotectedTrackedWebView(webView, owner, tab)
            },
            refreshPrimaryTrackedWebView: { [refreshPrimaryTrackedWebView] tab in
                refreshPrimaryTrackedWebView(tab)
            }
        )
    }
}
