import Foundation

@MainActor
final class BrowserWindowHistorySessionOwner {
    private let windowState: @MainActor (UUID) -> BrowserWindowState?
    private let allWindows: @MainActor () -> [BrowserWindowState]
    private let makeWindowSessionSnapshot: @MainActor (BrowserWindowState) -> WindowSessionSnapshot?
    private let windowDisplayTitle: @MainActor (BrowserWindowState) -> String
    private let recentlyClosedManager: @MainActor () -> RecentlyClosedManager
    private let lastSessionWindowsStore: @MainActor () -> LastSessionWindowsStore
    private let startupRestore: any BrowserStartupSessionRestoreProviding

    init(
        windowState: @escaping @MainActor (UUID) -> BrowserWindowState?,
        allWindows: @escaping @MainActor () -> [BrowserWindowState],
        makeWindowSessionSnapshot: @escaping @MainActor (BrowserWindowState) -> WindowSessionSnapshot?,
        windowDisplayTitle: @escaping @MainActor (BrowserWindowState) -> String,
        recentlyClosedManager: @escaping @MainActor () -> RecentlyClosedManager,
        lastSessionWindowsStore: @escaping @MainActor () -> LastSessionWindowsStore,
        startupRestore: any BrowserStartupSessionRestoreProviding
    ) {
        self.windowState = windowState
        self.allWindows = allWindows
        self.makeWindowSessionSnapshot = makeWindowSessionSnapshot
        self.windowDisplayTitle = windowDisplayTitle
        self.recentlyClosedManager = recentlyClosedManager
        self.lastSessionWindowsStore = lastSessionWindowsStore
        self.startupRestore = startupRestore
    }

    func handleWindowWillClose(_ windowId: UUID) {
        guard let windowState = windowState(windowId),
              !windowState.isIncognito
        else {
            refreshLastSessionWindowsStore(excludingWindowID: windowId)
            return
        }

        guard let snapshot = makeWindowSessionSnapshot(windowState) else {
            refreshLastSessionWindowsStore(excludingWindowID: windowId)
            return
        }
        if snapshot.currentTabId != nil || snapshot.activeSplitGroupId != nil || !snapshot.isShowingEmptyState {
            recentlyClosedManager().captureClosedWindow(
                title: windowDisplayTitle(windowState),
                session: snapshot
            )
        }

        refreshLastSessionWindowsStore(excludingWindowID: windowId)
    }

    func refreshLastSessionWindowsStore(excludingWindowID: UUID?) {
        if startupRestore.canOfferRestoreShortcut,
           let startupLastSessionTabSnapshot = startupRestore.tabSnapshot {
            lastSessionWindowsStore().updateSnapshots(
                startupRestore.windowSnapshots,
                tabSnapshot: startupLastSessionTabSnapshot
            )
            return
        }

        var snapshots = currentRegularWindowSnapshots(excludingWindowID: excludingWindowID)
        if snapshots.isEmpty, excludingWindowID != nil {
            snapshots = currentRegularWindowSnapshots(excludingWindowID: nil)
        }
        if snapshots.count > 1 {
            startupRestore.markRestoreOfferConsumed()
        }
        lastSessionWindowsStore().updateSnapshots(snapshots)
    }

    func currentRegularWindowSnapshots(
        excludingWindowID: UUID?
    ) -> [LastSessionWindowSnapshot] {
        allWindows()
            .filter { !$0.isIncognito }
            .filter { $0.id != excludingWindowID }
            .compactMap { windowState in
                guard let session = makeWindowSessionSnapshot(windowState) else {
                    return nil
                }
                return LastSessionWindowSnapshot(
                    id: windowState.id,
                    session: session
                )
            }
    }
}
