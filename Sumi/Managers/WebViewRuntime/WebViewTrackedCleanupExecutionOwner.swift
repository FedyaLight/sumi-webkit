//
//  WebViewTrackedCleanupExecutionOwner.swift
//  Sumi
//
//  Owns the execution order for unprotected tracked WebView cleanup.
//

import Foundation
import WebKit
import SumiWebRuntime

@MainActor
final class WebViewTrackedCleanupExecutionOwner {
    typealias DestructiveCleanupSuppressionFinisher = (WKWebView) -> Void
    typealias ProcessRecoveryCancellation = (WKWebView) -> Void
    typealias RuntimeObservationUninstaller = (WKWebView) -> Void
    typealias DeferredCommandPruner = (String) -> Void
    typealias FallbackCleanup = (WKWebView, UUID) -> Void
    typealias RecentVisibilityRemover = (TrackedWebViewOwner) -> Void

    struct Runtime {
        let cancelProcessRecovery: ProcessRecoveryCancellation
        let finishDestructiveCleanupSuppression: DestructiveCleanupSuppressionFinisher
        let uninstallRuntimeObservationsIfUntracked: RuntimeObservationUninstaller
        let pruneInvalidDeferredCommands: DeferredCommandPruner
        let fallbackCleanup: FallbackCleanup
        let forgetRecentVisibility: RecentVisibilityRemover
    }

    @discardableResult
    func cleanupUnprotectedTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        tab: (any WebRuntimeTabTeardownLifecycle)?,
        webViewSessions: WebViewSessionRepository,
        trackingLifecycleOwner: WebViewTrackingLifecycleOwner,
        runtime: Runtime
    ) -> Bool {
        runtime.cancelProcessRecovery(webView)
        runtime.finishDestructiveCleanupSuppression(webView)
        tab?.webViewsWillLeaveRuntime([webView])

        guard trackingLifecycleOwner.unregisterTrackedWebViewSlot(
            owner: owner,
            expectedWebView: webView,
            in: webViewSessions,
            removeFromContainers: { _ in },
            uninstallRuntimeObservationsIfUntracked: runtime
                .uninstallRuntimeObservationsIfUntracked,
            pruneInvalidDeferredCommands: runtime.pruneInvalidDeferredCommands,
            forgetRecentVisibility: runtime.forgetRecentVisibility
        ) != nil else {
            return false
        }

        if let tab {
            tab.destroyRetiredWebView(webView)
        } else {
            runtime.fallbackCleanup(webView, owner.tabID)
        }
        return true
    }
}
