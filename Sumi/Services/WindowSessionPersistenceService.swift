import Foundation

/// Builds and durably commits a window snapshot. Immediate persistence also
/// invalidates any older coalesced request for the same window.
@MainActor
final class WindowSessionPersistenceService {
    private let store: WindowSessionSnapshotStore
    private let scheduler: WindowSessionPersistenceScheduler
    private let snapshotFactory: WindowSessionSnapshotFactory

    init(
        store: WindowSessionSnapshotStore,
        scheduler: WindowSessionPersistenceScheduler,
        snapshotFactory: WindowSessionSnapshotFactory
    ) {
        self.store = store
        self.scheduler = scheduler
        self.snapshotFactory = snapshotFactory
    }

    func persist(_ windowState: BrowserWindowState) {
        scheduler.cancel(for: windowState.id)
        guard windowState.isIncognito == false else { return }
        _ = store.persist(snapshotFactory.make(for: windowState))
    }
}
