import Foundation

@MainActor
final class ClosedShortcutWindowQuery {
    private let windows: WindowRegistry

    init(windows: WindowRegistry) {
        self.windows = windows
    }

    func targetWindow(
        for shortcutState: RecentlyClosedShortcutLiveState,
        preferredWindow: BrowserWindowState? = nil
    ) -> BrowserWindowState? {
        if let preferredWindow {
            return preferredWindow
        }
        if let sourceWindowID = shortcutState.sourceWindowId,
           let sourceWindow = windows.windows[sourceWindowID] {
            return sourceWindow
        }
        return windows.activeWindow
    }
}
