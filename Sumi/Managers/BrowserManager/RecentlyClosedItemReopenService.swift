import Foundation

/// Reopens one recently-closed history item by dispatching it to the restore
/// service that owns the matching workflow, and removes the item from history
/// only after that service reports success (also consuming the startup
/// restore offer).
@MainActor
final class RecentlyClosedItemReopenService {
    private let recentlyClosedItems: @MainActor () -> RecentlyClosedManager
    private let startupRestore: any BrowserStartupSessionRestoreProviding
    private let tabRestore: ClosedTabRestoreService
    private let shortcutRestore: ClosedShortcutRestoreService
    private let windowReopen: any WindowSessionReopening

    /// Window reopening is serialized by the shared reopener; the handle is
    /// exposed so callers and tests can await completion explicitly.
    private(set) var pendingWindowReopenTask: Task<Void, Never>?

    isolated deinit {
        pendingWindowReopenTask?.cancel()
    }

    init(
        recentlyClosedItems: @escaping @MainActor () -> RecentlyClosedManager,
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

    func reopenMostRecentItem() {
        guard let item = recentlyClosedItems().mostRecentItem else { return }
        reopen(item)
    }

    func reopen(_ item: RecentlyClosedItem) {
        switch item {
        case .tab(let tabState):
            finalizeIfRestored(tabRestore.restore(tabState), item: item)
        case .shortcutLiveInstance(let shortcutState):
            finalizeIfRestored(shortcutRestore.restoreLiveInstance(shortcutState), item: item)
        case .shortcutLauncher(let launcherState):
            finalizeIfRestored(shortcutRestore.restoreLauncher(from: launcherState.pin), item: item)
        case .window(let windowState):
            let snapshot = LastSessionWindowSnapshot(
                id: windowState.sessionWindowId,
                session: windowState.session
            )
            reopenWindowItem(item, snapshot: snapshot)
        }
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
        recentlyClosedItems().remove(item)
        startupRestore.markRestoreOfferConsumed()
    }
}
