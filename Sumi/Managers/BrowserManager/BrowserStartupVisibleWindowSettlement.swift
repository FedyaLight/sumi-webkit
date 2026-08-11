import Foundation

@MainActor
final class BrowserStartupVisibleWindowSettlement {
    private let windows: WindowRegistry
    private let visuals: BrowserWindowVisualCoordinator
    private let commands: BrowserWebViewWindowCommandChannel

    init(
        windows: WindowRegistry,
        visuals: BrowserWindowVisualCoordinator,
        commands: BrowserWebViewWindowCommandChannel
    ) {
        self.windows = windows
        self.visuals = visuals
        self.commands = commands
    }

    func settleVisibleWindows() {
        for windowState in windows.allWindows {
            commands.retryPageMaterialization(in: windowState.id)
            visuals.schedulePrepareVisibleWebViews(for: windowState)
            visuals.refreshCompositor(for: windowState)
        }
    }
}
