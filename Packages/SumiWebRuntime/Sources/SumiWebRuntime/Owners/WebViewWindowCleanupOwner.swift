//
//  WebViewWindowCleanupOwner.swift
//  SumiWebRuntime
//
//  Owns window-scoped and app-wide cleanup of tracked WebViews, including the
//  registry/bookkeeping reset once every WebView is released.
//

import Foundation
import WebKit

/// Owns window-scoped and app-wide cleanup of tracked WebViews, including the
/// registry/bookkeeping reset once every WebView is released.
///
/// Visible preparation is reached only through
/// `WebRuntimeVisiblePreparationControlling`.
@MainActor
public final class WebViewWindowCleanupOwner {
    private let cleanupScopeOwner: WebViewCleanupScopeOwner
    private let webViewRegistry: WindowWebViewRegistry
    private let visibleWebViewRuntimeOwner: any WebRuntimeVisiblePreparationControlling
    private let mediaProtectionOwner: WebViewMediaProtectionOwner
    private let browserRuntimeContext: @MainActor () -> WebViewCoordinatorBrowserRuntimeContext?
    private let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
    private let enqueueDeferredProtectedCommand:
        @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool
    private let cleanupUnprotectedTrackedWebView:
        @MainActor (WKWebView, TrackedWebViewOwner, (any WebRuntimeTabHandle)?) -> Void
    private let refreshPrimaryTrackedWebView: @MainActor (any WebRuntimeTabHandle) -> Void
    private let removeCompositorContainerView: @MainActor (UUID) -> Void
    private let finishCleanupSuppression: @MainActor ([ObjectIdentifier]) -> Void

    public init(
        cleanupScopeOwner: WebViewCleanupScopeOwner,
        webViewRegistry: WindowWebViewRegistry,
        visibleWebViewRuntimeOwner: any WebRuntimeVisiblePreparationControlling,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        browserRuntimeContext: @escaping @MainActor () -> WebViewCoordinatorBrowserRuntimeContext?,
        isWebViewProtectedFromCompositorMutation: @escaping @MainActor (WKWebView) -> Bool,
        enqueueDeferredProtectedCommand:
            @escaping @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool,
        cleanupUnprotectedTrackedWebView:
            @escaping @MainActor (WKWebView, TrackedWebViewOwner, (any WebRuntimeTabHandle)?) -> Void,
        refreshPrimaryTrackedWebView: @escaping @MainActor (any WebRuntimeTabHandle) -> Void,
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

    public func cleanupWindow(_ windowId: UUID) {
        let signpostState = SumiWebRuntimeDiagnostics.beginInterval(
            "WebViewCoordinator.cleanupWindow"
        )
        defer {
            SumiWebRuntimeDiagnostics.endInterval(
                "WebViewCoordinator.cleanupWindow",
                signpostState
            )
        }

        visibleWebViewRuntimeOwner.cancelScheduledPreparation(for: windowId)
        cleanupScopeOwner.cleanupWindow(
            windowId,
            entries: webViewRegistry.trackedWebViews(in: windowId),
            runtime: scopeRuntime()
        )
        removeCompositorContainerView(windowId)
    }

    public func cleanupAllWebViews() {
        cleanupScopeOwner.cleanupAllWebViews(
            entries: webViewRegistry.trackedWebViews(),
            totalWebViewCount: webViewRegistry.totalTrackedWebViewCount,
            runtime: scopeRuntime()
        )

        if webViewRegistry.isEmpty {
            webViewRegistry.removeAll()
            visibleWebViewRuntimeOwner.resetWindowRegistrations()
            mediaProtectionOwner.removeVisualHandoffFullscreenAndNowPlayingState()
        }

        SumiWebRuntimeDiagnostics.debug(
            category: "WebViewCoordinator",
            "Completed full WebView cleanup."
        )

        finishCleanupSuppression(
            mediaProtectionOwner.pruneStaleBookkeeping(reason: "cleanupAllWebViews")
        )
    }

    private func scopeRuntime() -> WebViewCleanupScopeOwner.Runtime {
        let runtimeContext = browserRuntimeContext()
        return WebViewCleanupScopeOwner.Runtime(
            tabForID: { tabID in
                runtimeContext?.resolveWebRuntimeTab(tabID)
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
