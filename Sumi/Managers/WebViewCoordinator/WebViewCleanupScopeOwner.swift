//
//  WebViewCleanupScopeOwner.swift
//  Sumi
//
//  Owns cleanup orchestration for window/all tracked WebView scopes.
//

import Foundation
import WebKit

@MainActor
final class WebViewCleanupScopeOwner {
    typealias TabResolver = (UUID) -> Tab?
    typealias WebViewProtectionCheck = (WKWebView) -> Bool
    typealias ProtectedCommandEnqueuer = (DeferredWebViewCommand, WKWebView, String) -> Bool
    typealias UnprotectedTrackedCleanup = (WKWebView, TrackedWebViewOwner, Tab?, BrowserManager?) -> Void
    typealias PrimaryTrackedWebViewRefresh = (Tab, BrowserManager?) -> Void

    struct Runtime {
        let browserManager: BrowserManager?
        let tabForID: TabResolver
        let isWebViewProtectedFromCompositorMutation: WebViewProtectionCheck
        let enqueueDeferredProtectedCommand: ProtectedCommandEnqueuer
        let cleanupUnprotectedTrackedWebView: UnprotectedTrackedCleanup
        let refreshPrimaryTrackedWebView: PrimaryTrackedWebViewRefresh
    }

    func cleanupWindow(
        _ windowId: UUID,
        entries: [(TrackedWebViewOwner, WKWebView)],
        runtime: Runtime
    ) {
        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Cleaning up \(entries.count) WebViews for window \(windowId.uuidString)."
        }

        cleanup(
            entries,
            protectedCommand: .cleanupWindow(windowID: windowId),
            reason: "cleanupWindow",
            runtime: runtime
        ) { owner in
            "Cleaned up WebView for tab=\(owner.tabID.uuidString.prefix(8)) in window=\(windowId.uuidString.prefix(8))."
        }
    }

    func cleanupAllWebViews(
        entries: [(TrackedWebViewOwner, WKWebView)],
        totalWebViewCount: Int,
        runtime: Runtime
    ) {
        RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
            "Starting full WebView cleanup for \(totalWebViewCount) tracked views."
        }

        cleanup(
            entries,
            protectedCommand: .cleanupAllWebViews,
            reason: "cleanupAllWebViews",
            runtime: runtime
        ) { owner in
            "Cleaned up WebView for tab=\(owner.tabID.uuidString.prefix(8)) in window=\(owner.windowID.uuidString.prefix(8))."
        }
    }

    private func cleanup(
        _ entries: [(TrackedWebViewOwner, WKWebView)],
        protectedCommand: DeferredWebViewCommand,
        reason: String,
        runtime: Runtime,
        cleanedMessage: (TrackedWebViewOwner) -> String
    ) {
        for (owner, webView) in entries {
            if runtime.isWebViewProtectedFromCompositorMutation(webView) {
                _ = runtime.enqueueDeferredProtectedCommand(
                    protectedCommand,
                    webView,
                    reason
                )
                continue
            }

            let tab = runtime.tabForID(owner.tabID)
            runtime.cleanupUnprotectedTrackedWebView(
                webView,
                owner,
                tab,
                runtime.browserManager
            )
            if let tab {
                runtime.refreshPrimaryTrackedWebView(tab, runtime.browserManager)
            }

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                cleanedMessage(owner)
            }
        }
    }
}
