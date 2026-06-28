//
//  WebViewHiddenCloneEvictionOwner.swift
//  Sumi
//
//  Owns hidden clone eviction selection and sequencing.
//

import Foundation
import WebKit

@MainActor
final class WebViewHiddenCloneEvictionOwner {
    typealias TabResolver = (UUID) -> Tab?
    typealias LiveWebViews = (Tab) -> [WKWebView]
    typealias WebViewProtectionCheck = (WKWebView) -> Bool
    typealias ProtectedCommandEnqueuer = (DeferredWebViewCommand, WKWebView, String) -> Bool
    typealias UnprotectedTrackedCleanup = (WKWebView, TrackedWebViewOwner, Tab, BrowserManager) -> Void
    typealias PrimaryTrackedWebViewRefresh = (Tab, BrowserManager) -> Void

    struct Runtime {
        let tabForID: TabResolver
        let liveWebViews: LiveWebViews
        let isWebViewProtectedFromCompositorMutation: WebViewProtectionCheck
        let enqueueDeferredProtectedCommand: ProtectedCommandEnqueuer
        let cleanupUnprotectedTrackedWebView: UnprotectedTrackedCleanup
        let refreshPrimaryTrackedWebView: PrimaryTrackedWebViewRefresh
    }

    func evictHiddenWebViews(
        in windowId: UUID,
        visibleTabIDs: Set<UUID>,
        entries: [(TrackedWebViewOwner, WKWebView)],
        tabManager: TabManager,
        runtime: Runtime
    ) {
        let signpostState = PerformanceTrace.beginInterval("WebViewCoordinator.evictHiddenWebViews")
        defer {
            PerformanceTrace.endInterval("WebViewCoordinator.evictHiddenWebViews", signpostState)
        }

        let hiddenEntries = entries.filter { owner, _ in
            visibleTabIDs.contains(owner.tabID) == false
        }

        guard hiddenEntries.isEmpty == false else { return }

        guard let browserManager = tabManager.browserManager else { return }
        let globallyVisibleTabIDs = browserManager.tabSuspensionService
            .suspensionEvaluationContext()
            .visibleTabIDs

        for (owner, webView) in hiddenEntries.sorted(by: {
            if $0.0.tabID != $1.0.tabID {
                return $0.0.tabID.uuidString < $1.0.tabID.uuidString
            }
            return $0.0.windowID.uuidString < $1.0.windowID.uuidString
        }) {
            guard globallyVisibleTabIDs.contains(owner.tabID) else { continue }
            guard let tab = runtime.tabForID(owner.tabID) else { continue }
            guard runtime.liveWebViews(tab).count > 1 else { continue }

            if runtime.isWebViewProtectedFromCompositorMutation(webView) {
                _ = runtime.enqueueDeferredProtectedCommand(
                    .evictHiddenWebViews(windowID: windowId),
                    webView,
                    "hiddenCloneCleanup"
                )
                continue
            }

            runtime.cleanupUnprotectedTrackedWebView(
                webView,
                owner,
                tab,
                browserManager
            )
            runtime.refreshPrimaryTrackedWebView(tab, browserManager)

            RuntimeDiagnostics.debug(category: "WebViewCoordinator") {
                "Cleaned hidden clone for visible tab=\(owner.tabID.uuidString.prefix(8)) window=\(windowId.uuidString.prefix(8))."
            }
        }
    }
}
