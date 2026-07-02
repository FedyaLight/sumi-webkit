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

@MainActor
final class WebViewRuntimeAssembler {
    struct Dependencies {
        let runtimeContextStore: WebViewRuntimeContextStore
        let webViewRegistry: WindowWebViewRegistry
        let visibleWebViewRuntimeOwner: VisibleWebViewRuntimeOwner
        let hiddenCloneEvictionOwner: WebViewHiddenCloneEvictionOwner
        let registerTrackedWebView: @MainActor (WKWebView, UUID, UUID) -> Void
        let unregisterTrackedWebViewSlot:
            @MainActor (TrackedWebViewOwner, WKWebView?) -> WKWebView?
        let removeWebViewFromContainers: @MainActor (WKWebView) -> Void
        let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
        let enqueueDeferredProtectedCommand:
            @MainActor (DeferredWebViewCommand, WKWebView, String) -> Bool
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
            webViewRegistry: dependencies.webViewRegistry
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
            entries: dependencies.webViewRegistry.trackedWebViews(in: windowId),
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
                dependencies.enqueueDeferredProtectedCommand(command, webView, reason)
            },
            cleanupUnprotectedTrackedWebView: { [dependencies] webView, owner, tab in
                dependencies.cleanupUnprotectedTrackedWebView(webView, owner, tab)
            },
            refreshPrimaryTrackedWebView: { [dependencies] tab in
                dependencies.refreshPrimaryTrackedWebView(tab)
            }
        )
    }

    // MARK: - Assignment/Rebuild Runtime

    func assignmentRebuildRuntime() -> WebViewAssignmentRebuildOwner.Runtime {
        let runtimeContext = dependencies.runtimeContextStore.requireBrowser()
        return WebViewAssignmentRebuildOwner.Runtime(
            webViewRegistry: dependencies.webViewRegistry,
            initialDocumentWarmupRuntime: initialDocumentWarmupRuntime(),
            registerTrackedWebView: { [dependencies] webView, tabId, windowId in
                dependencies.registerTrackedWebView(webView, tabId, windowId)
            },
            unregisterTrackedWebViewSlot: { [dependencies] owner, expectedWebView in
                dependencies.unregisterTrackedWebViewSlot(owner, expectedWebView)
            },
            removeFromContainers: { [dependencies] webView in
                dependencies.removeWebViewFromContainers(webView)
            },
            isWebViewProtectedFromCompositorMutation: { [dependencies] webView in
                dependencies.isWebViewProtectedFromCompositorMutation(webView)
            },
            deferProtectedRebuild: { [dependencies] webView, tabID, preferredPrimaryWindowId in
                _ = dependencies.enqueueDeferredProtectedCommand(
                    .rebuildLiveWebViews(
                        tabID: tabID,
                        preferredPrimaryWindowID: preferredPrimaryWindowId
                    ),
                    webView,
                    "rebuildLiveWebViews"
                )
            },
            primaryCandidate: { [weak self] tabId in
                self?.preferredPrimaryWebViewCandidate(for: tabId)
            },
            liveWindowSelection: {
                .liveWindows(Set(runtimeContext.allWindows().map(\.id)))
            },
            refreshCompositor: { windowId in
                guard let windowState = runtimeContext.window(windowId) else {
                    return
                }
                runtimeContext.refreshCompositor(windowState)
            },
            notifyTabActivatedIfCurrent: { tab, windowId in
                guard let windowState = runtimeContext.window(windowId),
                      runtimeContext.currentTab(windowState)?.id == tab.id
                else {
                    return
                }
                runtimeContext.notifyTabActivatedIfLoaded(tab)
            }
        )
    }

    private func initialDocumentWarmupRuntime() -> InitialDocumentWarmupRuntime {
        let runtimeContext = dependencies.runtimeContextStore.requireInitialDocument()
        return InitialDocumentWarmupRuntime(
            needsInitialDocumentExtensionContextLoad: { profileId in
                runtimeContext.needsInitialDocumentExtensionContextLoad(profileId)
            },
            ensureInitialExtensionContextsLoaded: { profileId in
                await runtimeContext.ensureInitialExtensionContextsLoaded(profileId)
            },
            refreshCompositorForWindow: { windowId in
                runtimeContext.refreshCompositorForWindow(windowId)
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
            webViewRegistry: coordinator.webViewRegistry,
            visibleWebViewRuntimeOwner: coordinator.visibleWebViewRuntimeOwner,
            hiddenCloneEvictionOwner: coordinator.hiddenCloneEvictionOwner,
            registerTrackedWebView: { [weak coordinator] webView, tabId, windowId in
                coordinator?.setWebView(webView, for: tabId, in: windowId)
            },
            unregisterTrackedWebViewSlot: { [weak coordinator] owner, expectedWebView in
                coordinator?.unregisterTrackedWebViewSlot(
                    owner: owner,
                    expectedWebView: expectedWebView
                )
            },
            removeWebViewFromContainers: { [weak coordinator] webView in
                coordinator?.removeWebViewFromContainers(webView)
            },
            isWebViewProtectedFromCompositorMutation: { [weak coordinator] webView in
                coordinator?.isWebViewProtectedFromCompositorMutation(webView) ?? false
            },
            enqueueDeferredProtectedCommand: { [weak coordinator] command, webView, reason in
                coordinator?.enqueueDeferredProtectedCommand(
                    command,
                    for: webView,
                    reason: reason
                ) ?? false
            },
            resolvedTab: { [weak coordinator] tabID, runtimeContext in
                guard let coordinator else { return nil }
                if let runtimeContext {
                    return coordinator.resolvedTab(with: tabID, runtimeContext: runtimeContext)
                }
                return coordinator.resolvedTab(with: tabID)
            },
            trackedLiveWebViews: { [weak coordinator] tab in
                coordinator?.trackedLiveWebViews(for: tab) ?? []
            },
            cleanupUnprotectedTrackedWebView: { [weak coordinator] webView, owner, tab in
                coordinator?.cleanupUnprotectedTrackedWebView(
                    webView,
                    owner: owner,
                    tab: tab
                )
            },
            refreshPrimaryTrackedWebView: { [weak coordinator] tab in
                coordinator?.refreshPrimaryTrackedWebView(for: tab)
            }
        )
    }
}
