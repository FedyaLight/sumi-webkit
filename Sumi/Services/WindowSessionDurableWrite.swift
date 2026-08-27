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
        _ = store.enqueuePersist(snapshotFactory.make(for: windowState))
    }
}
