//
//  WebViewCleanupScopeOwner.swift
//  SumiWebRuntime
//
//  Owns cleanup orchestration for window/all tracked WebView scopes.
//

import Foundation
import WebKit

@MainActor
public final class WebViewCleanupScopeOwner {
    public typealias TabResolver = (UUID) -> (any WebRuntimeTabHandle)?
    public typealias WebViewProtectionCheck = (WKWebView) -> Bool
    public typealias ProtectedCommandEnqueuer = (DeferredWebViewCommand, WKWebView, String) -> Bool
    public typealias UnprotectedTrackedCleanup =
        (WKWebView, TrackedWebViewOwner, (any WebRuntimeTabHandle)?) -> Bool
    public typealias PrimaryTrackedWebViewRefresh = (any WebRuntimeTabHandle) -> Void

    public struct Runtime {
        public let tabForID: TabResolver
        public let isWebViewProtectedFromCompositorMutation: WebViewProtectionCheck
        public let enqueueDeferredProtectedCommand: ProtectedCommandEnqueuer
        public let cleanupUnprotectedTrackedWebView: UnprotectedTrackedCleanup
        public let refreshPrimaryTrackedWebView: PrimaryTrackedWebViewRefresh

        public init(
            tabForID: @escaping TabResolver,
            isWebViewProtectedFromCompositorMutation: @escaping WebViewProtectionCheck,
            enqueueDeferredProtectedCommand: @escaping ProtectedCommandEnqueuer,
            cleanupUnprotectedTrackedWebView: @escaping UnprotectedTrackedCleanup,
            refreshPrimaryTrackedWebView: @escaping PrimaryTrackedWebViewRefresh
        ) {
            self.tabForID = tabForID
            self.isWebViewProtectedFromCompositorMutation = isWebViewProtectedFromCompositorMutation
            self.enqueueDeferredProtectedCommand = enqueueDeferredProtectedCommand
            self.cleanupUnprotectedTrackedWebView = cleanupUnprotectedTrackedWebView
            self.refreshPrimaryTrackedWebView = refreshPrimaryTrackedWebView
        }
    }

    public init() {}

    public func cleanupWindow(
        _ windowId: UUID,
        entries: [(TrackedWebViewOwner, WKWebView)],
        runtime: Runtime
    ) {
        SumiWebRuntimeDiagnostics.debug(category: "WebViewCleanupScopeOwner") {
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

    public func cleanupAllWebViews(
        entries: [(TrackedWebViewOwner, WKWebView)],
        totalWebViewCount: Int,
        runtime: Runtime
    ) {
        SumiWebRuntimeDiagnostics.debug(category: "WebViewCleanupScopeOwner") {
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
                let wasScheduled = runtime.enqueueDeferredProtectedCommand(
                    protectedCommand,
                    webView,
                    reason
                )
                if wasScheduled {
                    continue
                }
                guard runtime.isWebViewProtectedFromCompositorMutation(webView) == false else {
                    SumiWebRuntimeDiagnostics.protectedWebViewTrace(
                        "Unable to schedule protected cleanup owner=\(owner) reason=\(reason)."
                    )
                    continue
                }
            }

            let tab = runtime.tabForID(owner.tabID)
            guard runtime.cleanupUnprotectedTrackedWebView(
                webView,
                owner,
                tab
            ) else {
                continue
            }
            if let tab {
                runtime.refreshPrimaryTrackedWebView(tab)
            }

            SumiWebRuntimeDiagnostics.debug(category: "WebViewCleanupScopeOwner") {
                cleanedMessage(owner)
            }
        }
    }
}
