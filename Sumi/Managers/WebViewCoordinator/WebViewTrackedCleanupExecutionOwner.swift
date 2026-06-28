//
//  WebViewTrackedCleanupExecutionOwner.swift
//  Sumi
//
//  Owns the execution order for unprotected tracked WebView cleanup.
//

import Foundation
import WebKit

@MainActor
final class WebViewTrackedCleanupExecutionOwner {
    typealias DestructiveCleanupSuppressionFinisher = (WKWebView) -> Void
    typealias ContainerRemoval = (WKWebView) -> Void
    typealias RuntimeObservationUninstaller = (WKWebView) -> Void
    typealias DeferredCommandPruner = (String) -> Void
    typealias FallbackCleanup = (WKWebView, UUID, BrowserManager?) -> Void

    struct Runtime {
        let finishDestructiveCleanupSuppression: DestructiveCleanupSuppressionFinisher
        let removeFromContainers: ContainerRemoval
        let uninstallRuntimeObservationsIfUntracked: RuntimeObservationUninstaller
        let pruneInvalidDeferredCommands: DeferredCommandPruner
        let fallbackCleanup: FallbackCleanup
    }

    func cleanupUnprotectedTrackedWebView(
        _ webView: WKWebView,
        owner: TrackedWebViewOwner,
        tab: Tab?,
        browserManager: BrowserManager?,
        webViewRegistry: WindowWebViewRegistry,
        trackingLifecycleOwner: WebViewTrackingLifecycleOwner,
        runtime: Runtime
    ) {
        runtime.finishDestructiveCleanupSuppression(webView)
        runtime.removeFromContainers(webView)
        _ = trackingLifecycleOwner.unregisterTrackedWebViewSlot(
            owner: owner,
            expectedWebView: webView,
            in: webViewRegistry,
            removeFromContainers: runtime.removeFromContainers,
            uninstallRuntimeObservationsIfUntracked: runtime
                .uninstallRuntimeObservationsIfUntracked,
            pruneInvalidDeferredCommands: runtime.pruneInvalidDeferredCommands
        )

        if let tab {
            tab.cleanupCloneWebView(webView)
        } else {
            runtime.fallbackCleanup(webView, owner.tabID, browserManager)
        }
    }
}
