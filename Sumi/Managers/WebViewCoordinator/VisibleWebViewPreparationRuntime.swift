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
    let canMaterializeWebViewDuringStartup: (Tab) -> Bool
    let markTabAccessed: (UUID) -> Void
    let evictHiddenWebViews: (UUID, Set<UUID>) -> Void
    let scheduleTabSuspensionReconcile: (String) -> Void
    let scheduleBackgroundMediaReconcile: (String) -> Void
    let refreshCompositor: (BrowserWindowState) -> Void
}
