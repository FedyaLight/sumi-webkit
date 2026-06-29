//
//  VisibleWebViewPreparationRuntime.swift
//  Sumi
//
//  Narrow dependency adapter for visible WebView preparation.
//

import Foundation

@MainActor
struct VisibleWebViewPreparationRuntime {
    let windowState: (UUID) -> BrowserWindowState?
    let currentTabId: (BrowserWindowState) -> UUID?
    let splitVisibleTabIds: (UUID) -> [UUID]
    let resolveTab: (UUID, BrowserWindowState) -> Tab?
    let canMaterializeNormalTabWebViewDuringStartup: (Tab) -> Bool
    let markTabAccessed: (UUID) -> Void
    let evictHiddenWebViews: (UUID, Set<UUID>) -> Void
    let scheduleTabSuspensionReconcile: (String) -> Void
    let scheduleBackgroundMediaReconcile: (String) -> Void
    let refreshCompositor: (BrowserWindowState) -> Void
}

extension VisibleWebViewPreparationRuntime {
    static func live(
        browserManager: BrowserManager,
        resolveTab: @escaping @MainActor (
            UUID,
            BrowserWindowState,
            BrowserManager
        ) -> Tab?,
        evictHiddenWebViews: @escaping @MainActor (
            UUID,
            Set<UUID>,
            TabManager
        ) -> Void
    ) -> Self {
        Self(
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            currentTabId: { [weak browserManager] windowState in
                browserManager?.currentTab(for: windowState)?.id
            },
            splitVisibleTabIds: { [weak browserManager] windowId in
                browserManager?.splitManager.visibleTabIds(for: windowId) ?? []
            },
            resolveTab: { [weak browserManager] tabId, windowState in
                guard let browserManager else { return nil }
                return resolveTab(tabId, windowState, browserManager)
            },
            canMaterializeNormalTabWebViewDuringStartup: { [weak browserManager] tab in
                browserManager?.canMaterializeNormalTabWebViewDuringStartup(tab) == true
            },
            markTabAccessed: { [weak browserManager] tabId in
                browserManager?.compositorManager.markTabAccessed(tabId)
            },
            evictHiddenWebViews: { [weak browserManager] windowId, visibleTabIDs in
                guard let browserManager else { return }
                evictHiddenWebViews(windowId, visibleTabIDs, browserManager.tabManager)
            },
            scheduleTabSuspensionReconcile: { [weak browserManager] reason in
                browserManager?.tabSuspensionService.scheduleProactiveTimerReconcile(
                    reason: reason
                )
            },
            scheduleBackgroundMediaReconcile: { [weak browserManager] reason in
                browserManager?.backgroundMediaOptimizationService.scheduleReconcile(
                    reason: reason
                )
            },
            refreshCompositor: { [weak browserManager] windowState in
                browserManager?.refreshCompositor(for: windowState)
            }
        )
    }
}
