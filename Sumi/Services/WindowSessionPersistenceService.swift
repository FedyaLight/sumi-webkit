import Foundation

/// A coalesced write carries only the dependencies required to commit the
/// durable single-window snapshot. Live archive projection is deliberately
/// owned by `WindowSessionPersistenceCoordinator`, so teardown can execute
/// this value without retaining or consulting live window-session services.
@MainActor
struct WindowSessionDurableWrite {
    let windowState: BrowserWindowState
    private let store: WindowSessionSnapshotStore
    private let snapshotFactory: WindowSessionSnapshotFactory

    var windowID: UUID { windowState.id }

    init(
        windowState: BrowserWindowState,
        store: WindowSessionSnapshotStore,
        snapshotFactory: WindowSessionSnapshotFactory
    ) {
        self.windowState = windowState
        self.store = store
        self.snapshotFactory = snapshotFactory
    }

    func commit() {
        guard windowState.isIncognito == false else { return }
        _ = store.persist(snapshotFactory.make(for: windowState))
    }
}

/// Builds and durably commits window snapshots. It has no scheduling or live
/// archive responsibility.
@MainActor
final class WindowSessionPersistenceService {
    private let store: WindowSessionSnapshotStore
    private let snapshotFactory: WindowSessionSnapshotFactory

    init(
        store: WindowSessionSnapshotStore,
        snapshotFactory: WindowSessionSnapshotFactory
    ) {
        self.store = store
        self.snapshotFactory = snapshotFactory
    }

    func persistDurableSnapshot(_ windowState: BrowserWindowState) {
        guard windowState.isIncognito == false else { return }
        _ = store.persist(snapshotFactory.make(for: windowState))
    }

    func durableWrite(
        for windowState: BrowserWindowState
    ) -> WindowSessionDurableWrite {
        WindowSessionDurableWrite(
            windowState: windowState,
            store: store,
            snapshotFactory: snapshotFactory
        )
    }
}
