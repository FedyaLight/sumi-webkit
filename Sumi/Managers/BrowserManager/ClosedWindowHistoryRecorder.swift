import Foundation

/// Records a meaningfully populated regular window into recently-closed
/// history at close time. Incognito windows and windows whose snapshot is
/// unavailable or fully empty never become history items. The recorder never
/// touches the last-session archive.
@MainActor
final class ClosedWindowHistoryRecorder {
    private let openWindows: OpenWindowSessionCatalog
    private let windowDisplayTitle: @MainActor (BrowserWindowState) -> String
    private let recentlyClosedManager: @MainActor () -> RecentlyClosedManager

    init(
        openWindows: OpenWindowSessionCatalog,
        windowDisplayTitle: @escaping @MainActor (BrowserWindowState) -> String,
        recentlyClosedManager: @escaping @MainActor () -> RecentlyClosedManager
    ) {
        self.openWindows = openWindows
        self.windowDisplayTitle = windowDisplayTitle
        self.recentlyClosedManager = recentlyClosedManager
    }

    func recordWindowWillClose(_ windowState: BrowserWindowState) {
        guard !windowState.isIncognito else { return }
        guard let snapshot = openWindows.snapshot(of: windowState) else {
            return
        }
        guard snapshot.currentTabId != nil
            || snapshot.splitSelection != nil
            || !snapshot.isShowingEmptyState
        else { return }
        recentlyClosedManager().captureClosedWindow(
            sessionWindowId: windowState.restorationState.restoredSessionWindowID ?? windowState.id,
            title: windowDisplayTitle(windowState),
            session: snapshot
        )
    }
}
