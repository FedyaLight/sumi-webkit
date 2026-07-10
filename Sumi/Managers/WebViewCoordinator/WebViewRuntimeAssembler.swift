//
//  WebViewRuntimeAssembler.swift
//  Sumi
//
//  Assembles the per-call Runtime adapter values that WebView owners consume,
//  bridging attached runtime contexts with coordinator-scoped services.
//

import AppKit
import Foundation
import WebKit
import SumiWebRuntime

@MainActor
final class WebViewRuntimeAssembler {
    struct Dependencies {
        let runtimeContextStore: WebViewRuntimeContextStore
        let webViewSessions: WebViewSessionRepository
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
        let resolvedTab: @MainActor (UUID, WebViewCoordinatorBrowserRuntimeContext?) -> Tab?
        let trackedLiveWebViews: @MainActor (Tab) -> [WKWebView]
        let cleanupUnprotectedTrackedWebView:
            @MainActor (WKWebView, TrackedWebViewOwner, Tab?) -> Void
        let refreshPrimaryTrackedWebView: @MainActor (Tab) -> Void
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    // MARK: - Visible Preparation Runtime

    func requireVisiblePreparationRuntime() -> VisibleWebViewPreparationRuntime {
        visiblePreparationRuntime(context: dependencies.runtimeContextStore.requireVisible())
    }

    func visiblePreparationRuntime(
        context: WebViewCoordinatorVisibleRuntimeContext
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
                    globallyVisibleTabIDs: context.globallyVisibleTabIDs,
                    runtimeContext: nil
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

    func evictHiddenWebViews(
        in windowId: UUID,
        visibleTabIDs: Set<UUID>,
        globallyVisibleTabIDs: @escaping @MainActor () -> Set<UUID>,
        runtimeContext: WebViewCoordinatorBrowserRuntimeContext?
    ) {
        dependencies.hiddenCloneEvictionOwner.evictHiddenWebViews(
            in: windowId,
            visibleTabIDs: visibleTabIDs,
            entries: dependencies.webViewSessions.trackedWebViews(in: windowId),
            runtime: evictionRuntime(
                globallyVisibleTabIDs: globallyVisibleTabIDs,
                runtimeContext: runtimeContext
            )
        )
    }

    private func evictionRuntime(
        globallyVisibleTabIDs: @escaping @MainActor () -> Set<UUID>,
        runtimeContext: WebViewCoordinatorBrowserRuntimeContext?
    ) -> WebViewHiddenCloneEvictionOwner.Runtime {
        WebViewHiddenCloneEvictionOwner.Runtime(
            tabForID: { [dependencies] tabID in
                dependencies.resolvedTab(tabID, runtimeContext)
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
        let runtimeContext = dependencies.runtimeContextStore.requireShutdown()
        return SumiWebViewShutdown.NormalTabRuntime(
            cleanupUserScripts: { controller, webViewId in
                runtimeContext.cleanupUserScripts(controller, webViewId)
            },
            removeWebViewFromContainers: { [dependencies] webView in
                dependencies.removeWebViewFromContainers(webView)
            }
        )
    }
}

extension WebViewRuntimeAssembler.Dependencies {
    @MainActor
    static func live(coordinator: WebViewCoordinator) -> Self {
        Self(
            runtimeContextStore: coordinator.runtimeContextStore,
            webViewSessions: coordinator.webViewSessions,
            visibleWebViewRuntimeOwner: coordinator.visibleWebViewRuntimeOwner,
            hiddenCloneEvictionOwner: coordinator.hiddenCloneEvictionOwner,
            removeWebViewFromContainers: { [weak coordinator] webView in
                coordinator?.compositorRuntime.removeWebViewFromContainers(webView)
            },
            isWebViewProtectedFromCompositorMutation: { [weak coordinator] webView in
                coordinator?.protectionRuntime.isProtected(webView) ?? false
            },
            enqueueDeferredProtectedCommand: { [weak coordinator] command, webView, reason in
                coordinator?.protectionRuntime.schedule(
                    command,
                    for: webView,
                    reason: reason
                ) ?? .notProtected
            },
            resolvedTab: { [weak coordinator] tabID, runtimeContext in
                guard let coordinator else { return nil }
                return coordinator.runtimeTabs.resolve(
                    tabID,
                    runtime: runtimeContext
                        ?? coordinator.runtimeContextStore.requireBrowser()
                )
            },
            trackedLiveWebViews: { [weak coordinator] tab in
                coordinator?.ownershipQuery.trackedLiveWebViews(for: tab) ?? []
            },
            cleanupUnprotectedTrackedWebView: { [weak coordinator] webView, owner, tab in
                coordinator?.lifecycleService.cleanupUnprotectedTrackedWebView(
                    webView,
                    owner: owner,
                    tab: tab
                )
            },
            refreshPrimaryTrackedWebView: { [weak coordinator] tab in
                coordinator?.tabWebViewMaterialization.refreshPrimary(for: tab)
            }
        )
    }
}
