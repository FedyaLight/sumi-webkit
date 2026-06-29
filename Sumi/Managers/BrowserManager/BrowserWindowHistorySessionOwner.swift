import Foundation

@MainActor
final class BrowserWindowHistorySessionOwner {
    struct Dependencies {
        let windowState: @MainActor (UUID) -> BrowserWindowState?
        let allWindows: @MainActor () -> [BrowserWindowState]
        let makeWindowSessionSnapshot: @MainActor (BrowserWindowState) -> WindowSessionSnapshot?
        let windowDisplayTitle: @MainActor (BrowserWindowState) -> String
        let recentlyClosedManager: @MainActor () -> RecentlyClosedManager
        let lastSessionWindowsStore: @MainActor () -> LastSessionWindowsStore
        let startupRestore: any BrowserStartupSessionRestoreProviding
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func handleWindowWillClose(_ windowId: UUID) {
        guard let windowState = dependencies.windowState(windowId),
              !windowState.isIncognito
        else {
            refreshLastSessionWindowsStore(excludingWindowID: windowId)
            return
        }

        guard let snapshot = dependencies.makeWindowSessionSnapshot(windowState) else {
            refreshLastSessionWindowsStore(excludingWindowID: windowId)
            return
        }
        if snapshot.currentTabId != nil || snapshot.splitSession != nil || !snapshot.isShowingEmptyState {
            dependencies.recentlyClosedManager().captureClosedWindow(
                title: dependencies.windowDisplayTitle(windowState),
                session: snapshot
            )
        }

        refreshLastSessionWindowsStore(excludingWindowID: windowId)
    }

    func refreshLastSessionWindowsStore(excludingWindowID: UUID?) {
        if dependencies.startupRestore.canOfferRestoreShortcut,
           let startupLastSessionTabSnapshot = dependencies.startupRestore.tabSnapshot {
            dependencies.lastSessionWindowsStore().updateSnapshots(
                dependencies.startupRestore.windowSnapshots,
                tabSnapshot: startupLastSessionTabSnapshot
            )
            return
        }

        var snapshots = currentRegularWindowSnapshots(excludingWindowID: excludingWindowID)
        if snapshots.isEmpty, excludingWindowID != nil {
            snapshots = currentRegularWindowSnapshots(excludingWindowID: nil)
        }
        if snapshots.count > 1 {
            dependencies.startupRestore.markRestoreOfferConsumed()
        }
        dependencies.lastSessionWindowsStore().updateSnapshots(snapshots)
    }

    func currentRegularWindowSnapshots(
        excludingWindowID: UUID?
    ) -> [LastSessionWindowSnapshot] {
        dependencies.allWindows()
            .filter { !$0.isIncognito }
            .filter { $0.id != excludingWindowID }
            .compactMap { windowState in
                guard let session = dependencies.makeWindowSessionSnapshot(windowState) else {
                    return nil
                }
                return LastSessionWindowSnapshot(
                    id: windowState.id,
                    session: session
                )
            }
    }
}

extension BrowserWindowHistorySessionOwner.Dependencies {
    @MainActor
    static func live(browserManager: BrowserManager) -> Self {
        let startupRestoreOwner = browserManager.startupSessionRestoreOwner
        return Self(
            windowState: { [weak browserManager] windowId in
                browserManager?.windowRegistry?.windows[windowId]
            },
            allWindows: { [weak browserManager] in
                browserManager?.windowRegistry?.allWindows ?? []
            },
            makeWindowSessionSnapshot: { [weak browserManager] windowState in
                guard let browserManager else { return nil }
                return browserManager.windowSessionService.makeWindowSessionSnapshot(
                    for: windowState,
                    delegate: browserManager
                )
            },
            windowDisplayTitle: { [weak browserManager] windowState in
                browserManager?.windowDisplayTitle(for: windowState) ?? ""
            },
            recentlyClosedManager: {
                [weak browserManager, recentlyClosedManager = browserManager.recentlyClosedManager] in
                browserManager?.recentlyClosedManager ?? recentlyClosedManager
            },
            lastSessionWindowsStore: {
                [weak browserManager, lastSessionWindowsStore = browserManager.lastSessionWindowsStore] in
                browserManager?.lastSessionWindowsStore ?? lastSessionWindowsStore
            },
            startupRestore: startupRestoreOwner
        )
    }
}
