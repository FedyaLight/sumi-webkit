import Foundation

/// Records a meaningfully populated regular window into recently-closed
/// history at close time. Incognito windows and windows whose snapshot is
/// unavailable or fully empty never become history items. The recorder never
/// touches the last-session archive.
@MainActor
final class ClosedWindowHistoryRecorder {
    private let snapshots: WindowSessionSnapshotFactory
    private let titles: ClosedWindowDisplayTitleProjection
    private let recentlyClosedManager: RecentlyClosedManager

    init(
        snapshots: WindowSessionSnapshotFactory,
        titles: ClosedWindowDisplayTitleProjection,
        recentlyClosedManager: RecentlyClosedManager
    ) {
        self.snapshots = snapshots
        self.titles = titles
        self.recentlyClosedManager = recentlyClosedManager
    }

    func recordWindowWillClose(_ windowState: BrowserWindowState) {
        guard !windowState.isIncognito else { return }
        let snapshot = snapshots.make(for: windowState)
        guard snapshot.currentTabId != nil
            || snapshot.splitSelection != nil
            || !snapshot.isShowingEmptyState
        else { return }
        recentlyClosedManager.captureClosedWindow(
            sessionWindowId: windowState.restorationState.restoredSessionWindowID ?? windowState.id,
            title: titles.title(for: windowState),
            session: snapshot
        )
    }
}
