import Foundation

/// Process-lifetime durable window-session resources. The snapshot store and
/// debounce scheduler are created together, consumed together by the session
/// services, and synchronously drained together when the browser root exits.
@MainActor
final class WindowSessionPersistenceRuntime {
    let snapshotStore: WindowSessionSnapshotStore
    let scheduler = WindowSessionPersistenceScheduler()

    init(snapshotStore: WindowSessionSnapshotStore) {
        self.snapshotStore = snapshotStore
    }

    func flushForBrowserRuntimeTeardown() {
        scheduler.flushDurableStateForRuntimeTeardown()
        snapshotStore.flushPendingPersistence()
    }
}
