import Foundation

@MainActor
final class BrowserStartupVisibleWindowSettlement {
    private let windows: WindowRegistry
    private let visuals: BrowserWindowVisualCoordinator

    init(
        windows: WindowRegistry,
        visuals: BrowserWindowVisualCoordinator
    ) {
        self.windows = windows
        self.visuals = visuals
    }

    func settleVisibleWindows() {
        for windowState in windows.allWindows {
            visuals.schedulePrepareVisibleWebViews(for: windowState)
            visuals.refreshCompositor(for: windowState)
        }
    }
}
