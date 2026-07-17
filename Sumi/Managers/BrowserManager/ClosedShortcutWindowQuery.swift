import Foundation

@MainActor
final class ClosedShortcutWindowQuery {
    private let windows: WindowRegistry

    init(windows: WindowRegistry) {
        self.windows = windows
    }

    func targetWindow(
        for shortcutState: RecentlyClosedShortcutLiveState
    ) -> BrowserWindowState? {
        if let sourceWindowID = shortcutState.sourceWindowId,
           let sourceWindow = windows.windows[sourceWindowID] {
            return sourceWindow
        }
        return windows.activeWindow
    }
}
