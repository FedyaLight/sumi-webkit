//
//  VisibleWebViewPreparationRuntime.swift
//  SumiWebRuntime
//
//  Narrow dependency adapter for visible WebView preparation.
//

import Foundation

@MainActor
public struct VisibleWebViewPreparationRuntime {
    public let windowState: (UUID) -> (any WebRuntimeWindowHandle)?
    public let currentTabId: (any WebRuntimeWindowHandle) -> UUID?
    public let splitVisibleTabIds: (UUID) -> [UUID]
    public let resolveTab: (UUID, any WebRuntimeWindowHandle) -> (any WebRuntimeTabHandle)?
    public let canMaterializeWebViewDuringStartup: (any WebRuntimeTabHandle) -> Bool
    public let markTabAccessed: (UUID) -> Void
    public let evictHiddenWebViews: (UUID, Set<UUID>) -> Void
    public let scheduleTabSuspensionReconcile: (String) -> Void
    public let scheduleBackgroundMediaReconcile: (String) -> Void
    public let refreshCompositor: (UUID) -> Void

    public init(
        windowState: @escaping (UUID) -> (any WebRuntimeWindowHandle)?,
        currentTabId: @escaping (any WebRuntimeWindowHandle) -> UUID?,
        splitVisibleTabIds: @escaping (UUID) -> [UUID],
        resolveTab: @escaping (UUID, any WebRuntimeWindowHandle) -> (any WebRuntimeTabHandle)?,
        canMaterializeWebViewDuringStartup: @escaping (any WebRuntimeTabHandle) -> Bool,
        markTabAccessed: @escaping (UUID) -> Void,
        evictHiddenWebViews: @escaping (UUID, Set<UUID>) -> Void,
        scheduleTabSuspensionReconcile: @escaping (String) -> Void,
        scheduleBackgroundMediaReconcile: @escaping (String) -> Void,
        refreshCompositor: @escaping (UUID) -> Void
    ) {
        self.windowState = windowState
        self.currentTabId = currentTabId
        self.splitVisibleTabIds = splitVisibleTabIds
        self.resolveTab = resolveTab
        self.canMaterializeWebViewDuringStartup = canMaterializeWebViewDuringStartup
        self.markTabAccessed = markTabAccessed
        self.evictHiddenWebViews = evictHiddenWebViews
        self.scheduleTabSuspensionReconcile = scheduleTabSuspensionReconcile
        self.scheduleBackgroundMediaReconcile = scheduleBackgroundMediaReconcile
        self.refreshCompositor = refreshCompositor
    }
}
