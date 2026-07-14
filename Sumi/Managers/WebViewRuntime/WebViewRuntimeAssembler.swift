//
//  WebViewRuntimeAssembler.swift
//  Sumi
//
//  Assembles the per-call Runtime adapter values that WebView owners consume,
//  bridging attached runtime contexts with graph-scoped services.
//

import AppKit
import Foundation
import WebKit
import SumiWebRuntime

@MainActor
final class WebViewRuntimeAssembler {
    struct Dependencies {
        let webViewSessions: WebViewSessionRepository
        let visibleContext: WebViewVisibleRuntimeContext
        let visibleWebViewRuntimeOwner: VisibleWebViewRuntimeOwner
        let hiddenCloneEvictionOwner: WebViewHiddenCloneEvictionOwner
        let removeWebViewFromContainers: @MainActor (WKWebView) -> Void
        let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
        let enqueueDeferredProtectedCommand:
            @MainActor (
                DeferredWebViewCommand,
                WKWebView,
                String
            ) -> DeferredProtectedCommandSchedulingOutcome
        let resolvedTab: @MainActor (UUID) -> Tab?
        let trackedLiveWebViews: @MainActor (Tab) -> [WKWebView]
        let cleanupUnprotectedTrackedWebView:
            @MainActor (WKWebView, TrackedWebViewOwner, Tab?) -> Bool
        let refreshPrimaryTrackedWebView: @MainActor (Tab) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Visible Preparation Runtime

    func requireVisiblePreparationRuntime() -> VisibleWebViewPreparationRuntime {
        visiblePreparationRuntime(context: dependencies.visibleContext)
    }

    func visiblePreparationRuntime(
        context: WebViewVisibleRuntimeContext
    ) -> VisibleWebViewPreparationRuntime {
        VisibleWebViewPreparationRuntime(
            windowState: context.windowState,
            currentTabId: context.currentTabId,
            splitVisibleTabIds: context.splitVisibleTabIds,
            resolveTab: context.resolveTab,
            canMaterializeWebViewDuringStartup: context.canMaterializeWebViewDuringStartup,
            markTabAccessed: context.markTabAccessed,
            evictHiddenWebViews: { [weak self] windowId, visibleTabIDs in
                guard let self else { return }
                evictHiddenWebViews(
                    in: windowId,
                    visibleTabIDs: visibleTabIDs,
                    globallyVisibleTabIDs: context.globallyVisibleTabIDs
                )
            },
            scheduleTabSuspensionReconcile: context.scheduleTabSuspensionReconcile,
            scheduleBackgroundMediaReconcile: context.scheduleBackgroundMediaReconcile,
            refreshCompositor: context.refreshCompositor
        )
    }

    func preferredPrimaryWebViewCandidate(
        for tabId: UUID
    ) -> (owner: TrackedWebViewOwner, webView: WKWebView)? {
        dependencies.visibleWebViewRuntimeOwner.preferredPrimaryWebViewCandidate(
            for: tabId,
            runtime: requireVisiblePreparationRuntime(),
            webViewSessions: dependencies.webViewSessions
        )
    }

    // MARK: - Hidden Clone Eviction

    @discardableResult
    func evictHiddenWebViews(
        in windowId: UUID,
        visibleTabIDs: Set<UUID>,
        globallyVisibleTabIDs: @escaping @MainActor () -> Set<UUID>
    ) -> Bool {
        dependencies.hiddenCloneEvictionOwner.evictHiddenWebViews(
            in: windowId,
            visibleTabIDs: visibleTabIDs,
            entries: dependencies.webViewSessions.trackedWebViews(in: windowId),
            runtime: evictionRuntime(
                globallyVisibleTabIDs: globallyVisibleTabIDs
            )
        )
    }

    private func evictionRuntime(
        globallyVisibleTabIDs: @escaping @MainActor () -> Set<UUID>
    ) -> WebViewHiddenCloneEvictionOwner.Runtime {
        WebViewHiddenCloneEvictionOwner.Runtime(
            tabForID: { [dependencies] tabID in
                dependencies.resolvedTab(tabID)
            },
            liveWebViews: { [dependencies] tab in
                dependencies.trackedLiveWebViews(tab)
            },
            globallyVisibleTabIDs: globallyVisibleTabIDs,
            isWebViewProtectedFromCompositorMutation: { [dependencies] webView in
                dependencies.isWebViewProtectedFromCompositorMutation(webView)
            },
            enqueueDeferredProtectedCommand: { [dependencies] command, webView, reason in
                return dependencies.enqueueDeferredProtectedCommand(
                    command,
                    webView,
                    reason
                ).wasScheduled
            },
            cleanupUnprotectedTrackedWebView: { [dependencies] webView, owner, tab in
                dependencies.cleanupUnprotectedTrackedWebView(webView, owner, tab)
            },
            refreshPrimaryTrackedWebView: { [dependencies] tab in
                dependencies.refreshPrimaryTrackedWebView(tab)
            }
        )
    }

    // MARK: - Shutdown Runtime

    func shutdownRuntime() -> SumiWebViewShutdown.NormalTabRuntime {
        return SumiWebViewShutdown.NormalTabRuntime(
            removeWebViewFromContainers: { [dependencies] webView in
                dependencies.removeWebViewFromContainers(webView)
            }
        )
    }
}
