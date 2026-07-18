import Foundation

/// Restores one history item and removes it only after a successful restore.
@MainActor
final class RecentlyClosedItemReopenService {
    private let recentlyClosedItems: RecentlyClosedManager
    private let startupRestore: any BrowserStartupSessionRestoreProviding
    private let tabRestore: ClosedTabRestoreService
    private let shortcutRestore: ClosedShortcutRestoreService
    private let windowReopen: any WindowSessionReopening

    private(set) var pendingWindowReopenTask: Task<Void, Never>?

    isolated deinit { pendingWindowReopenTask?.cancel() }

    init(
        recentlyClosedItems: RecentlyClosedManager,
        startupRestore: any BrowserStartupSessionRestoreProviding,
        tabRestore: ClosedTabRestoreService,
        shortcutRestore: ClosedShortcutRestoreService,
        windowReopen: any WindowSessionReopening
    ) {
        self.recentlyClosedItems = recentlyClosedItems
        self.startupRestore = startupRestore
        self.tabRestore = tabRestore
        self.shortcutRestore = shortcutRestore
        self.windowReopen = windowReopen
    }

    func reopenMostRecentItem(in windowState: BrowserWindowState? = nil) {
        guard let item = recentlyClosedItems.mostRecentItem else { return }
        reopen(item, in: windowState)
    }

    func reopen(_ item: RecentlyClosedItem, in windowState: BrowserWindowState? = nil) {
        let didRestore: Bool
        switch item {
        case .tab(let tabState):
            didRestore = tabRestore.restore(tabState, in: windowState)
        case .shortcutLiveInstance(let shortcutState):
            didRestore = shortcutRestore.restoreLiveInstance(shortcutState, in: windowState)
        case .shortcutLauncher(let launcherState):
            didRestore = shortcutRestore.restoreLauncher(from: launcherState.pin, in: windowState)
        case .window(let windowState):
            reopenWindowItem(
                item,
                snapshot: LastSessionWindowSnapshot(
                    id: windowState.sessionWindowId,
                    session: windowState.session
                )
            )
            return
        }
        finalizeIfRestored(didRestore, item: item)
    }

    private func reopenWindowItem(
        _ item: RecentlyClosedItem,
        snapshot: LastSessionWindowSnapshot
    ) {
        guard pendingWindowReopenTask == nil else { return }
        pendingWindowReopenTask = Task { @MainActor [windowReopen, weak self] in
            let didReopen = await windowReopen.reopenWindow(from: snapshot)
            guard Task.isCancelled == false, let self else { return }
            self.finalizeIfRestored(didReopen, item: item)
            self.pendingWindowReopenTask = nil
        }
    }

    private func finalizeIfRestored(_ didRestore: Bool, item: RecentlyClosedItem) {
        guard didRestore else { return }
        recentlyClosedItems.remove(item)
        startupRestore.markRestoreOfferConsumed()
    }
}
