import Foundation

@MainActor
struct WebViewCoordinatorVisibleRuntimeContext {
    let windowState: (UUID) -> BrowserWindowState?
    let currentTabId: (BrowserWindowState) -> UUID?
    let splitVisibleTabIds: (UUID) -> [UUID]
    let resolveTab: (UUID, BrowserWindowState) -> Tab?
    let canMaterializeWebViewDuringStartup: (Tab) -> Bool
    let markTabAccessed: (UUID) -> Void
    let globallyVisibleTabIDs: @MainActor @Sendable () -> Set<UUID>
    let scheduleTabSuspensionReconcile: (String) -> Void
    let scheduleBackgroundMediaReconcile: (String) -> Void
    let refreshCompositor: (BrowserWindowState) -> Void
}
