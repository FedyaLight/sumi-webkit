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
    private let webViewSessions: WebViewSessionRepository
    private let visibleWebViewRuntimeOwner: any WebRuntimeVisiblePreparationControlling
    private let mediaProtectionOwner: WebViewMediaProtectionOwner
    private let tabForID: @MainActor (UUID) -> (any WebRuntimeTabHandle)?
    private let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
    private let enqueueDeferredProtectedCommand:
        @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool
    private let cleanupUnprotectedTrackedWebView:
        @MainActor (WKWebView, TrackedWebViewOwner, (any WebRuntimeTabHandle)?) -> Bool
    private let refreshPrimaryTrackedWebView: @MainActor (any WebRuntimeTabHandle) -> Void
    private let removeCompositorContainerView: @MainActor (UUID) -> Void
    private let flushDeferredProtectedCommands: @MainActor (ObjectIdentifier) -> Void
    private let finishCleanupSuppression: @MainActor ([ObjectIdentifier]) -> Void

    public init(
        cleanupScopeOwner: WebViewCleanupScopeOwner,
        webViewSessions: WebViewSessionRepository,
        visibleWebViewRuntimeOwner: any WebRuntimeVisiblePreparationControlling,
        mediaProtectionOwner: WebViewMediaProtectionOwner,
        tabForID: @escaping @MainActor (UUID) -> (any WebRuntimeTabHandle)?,
        isWebViewProtectedFromCompositorMutation: @escaping @MainActor (WKWebView) -> Bool,
        enqueueDeferredProtectedCommand:
            @escaping @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool,
        cleanupUnprotectedTrackedWebView:
            @escaping @MainActor (WKWebView, TrackedWebViewOwner, (any WebRuntimeTabHandle)?) -> Bool,
        refreshPrimaryTrackedWebView: @escaping @MainActor (any WebRuntimeTabHandle) -> Void,
        removeCompositorContainerView: @escaping @MainActor (UUID) -> Void,
        flushDeferredProtectedCommands: @escaping @MainActor (ObjectIdentifier) -> Void,
        finishCleanupSuppression: @escaping @MainActor ([ObjectIdentifier]) -> Void
    ) {
        self.cleanupScopeOwner = cleanupScopeOwner
        self.webViewSessions = webViewSessions
        self.visibleWebViewRuntimeOwner = visibleWebViewRuntimeOwner
        self.mediaProtectionOwner = mediaProtectionOwner
        self.tabForID = tabForID
        self.isWebViewProtectedFromCompositorMutation = isWebViewProtectedFromCompositorMutation
        self.enqueueDeferredProtectedCommand = enqueueDeferredProtectedCommand
        self.cleanupUnprotectedTrackedWebView = cleanupUnprotectedTrackedWebView
        self.refreshPrimaryTrackedWebView = refreshPrimaryTrackedWebView
        self.removeCompositorContainerView = removeCompositorContainerView
        self.flushDeferredProtectedCommands = flushDeferredProtectedCommands
        self.finishCleanupSuppression = finishCleanupSuppression
    }

    @discardableResult
    public func cleanupWindow(_ windowId: UUID) -> Bool {
        let signpostState = SumiWebRuntimeDiagnostics.beginInterval(
            "WebViewWindowCleanupOwner.cleanupWindow"
        )
        defer {
            SumiWebRuntimeDiagnostics.endInterval(
                "WebViewWindowCleanupOwner.cleanupWindow",
                signpostState
            )
        }

        visibleWebViewRuntimeOwner.cancelScheduledPreparation(for: windowId)
        cleanupScopeOwner.cleanupWindow(
            windowId,
            entries: webViewSessions.queries.trackedWebViews(in: windowId),
            runtime: scopeRuntime()
        )
        let didDrainWindow = webViewSessions.queries
            .trackedWebViews(in: windowId)
            .isEmpty
        if didDrainWindow {
            removeCompositorContainerView(windowId)
        }
        return didDrainWindow
    }

    @discardableResult
    public func cleanupAllWebViews() -> Bool {
        cleanupScopeOwner.cleanupAllWebViews(
            entries: webViewSessions.queries.trackedWebViews(),
            totalWebViewCount: webViewSessions.queries.totalTrackedWebViewCount,
            runtime: scopeRuntime()
        )

        let didDrainRuntime = webViewSessions.queries.isTrackingEmpty
        if didDrainRuntime {
            visibleWebViewRuntimeOwner.resetWindowRegistrations()
            let newlyUnprotectedSourceIDs = mediaProtectionOwner
                .removeVisualHandoffState()
            newlyUnprotectedSourceIDs.forEach(flushDeferredProtectedCommands)
        }

        SumiWebRuntimeDiagnostics.debug(
            category: "WebViewWindowCleanupOwner",
            "Completed full WebView cleanup."
        )

        finishCleanupSuppression(
            mediaProtectionOwner.pruneStaleBookkeeping(reason: "cleanupAllWebViews")
        )
        return didDrainRuntime
    }

    private func scopeRuntime() -> WebViewCleanupScopeOwner.Runtime {
        return WebViewCleanupScopeOwner.Runtime(
            tabForID: { [tabForID] tabID in
                tabForID(tabID)
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
