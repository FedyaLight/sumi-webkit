import Foundation

@MainActor
final class BrowserStartupVisibleWindowSettlement {
    private let windows: WindowRegistry
    private let visuals: BrowserWindowVisualCoordinator
    private let retryMaterialization: @MainActor (BrowserWindowState) -> Void

    init(
        windows: WindowRegistry,
        visuals: BrowserWindowVisualCoordinator,
        retryMaterialization: @escaping @MainActor (BrowserWindowState) -> Void
    ) {
        self.windows = windows
        self.visuals = visuals
        self.retryMaterialization = retryMaterialization
    }

    func settleVisibleWindows() {
        for windowState in windows.allWindows {
            retryMaterialization(windowState)
            visuals.schedulePrepareVisibleWebViews(for: windowState)
            visuals.refreshCompositor(for: windowState)
        }
    }
}
