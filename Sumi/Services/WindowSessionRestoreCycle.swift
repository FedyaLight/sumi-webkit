import Foundation

/// Owns the one-shot global snapshot claim for a browser-window cycle.
@MainActor
final class WindowSessionRestoreCycle {
    private var didClaimGlobalSnapshot = false

    func claimSnapshot(
        from store: WindowSessionSnapshotStore,
        for windowState: BrowserWindowState
    ) -> WindowSessionSnapshot? {
        guard windowState.isIncognito == false,
              didClaimGlobalSnapshot == false else {
            return nil
        }

        guard case .loaded(let snapshot, _) = store.loadResult() else {
            return nil
        }

        didClaimGlobalSnapshot = true
        return snapshot
    }

    func reset(store: WindowSessionSnapshotStore) {
        didClaimGlobalSnapshot = false
        store.resetCycleCache()
    }
}
