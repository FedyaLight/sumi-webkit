import Foundation

@MainActor
extension BrowserManager {
    func composeWindowSessionHistory() -> WindowSessionHistoryServices {
        WindowSessionHistoryServices.live(
            browserManager: self,
            snapshotFactory: windowSessionSnapshotFactory,
            startupRestore: startupSessionRestoreOwner
        )
    }

    func composeWindowSessionPersistence()
        -> WindowSessionPersistenceCoordinator {
        WindowSessionPersistenceCoordinator(
            persistence: WindowSessionPersistenceService(
                store: windowSessionPersistence.snapshotStore,
                snapshotFactory: windowSessionSnapshotFactory
            ),
            scheduler: windowSessionPersistence.scheduler,
            openWindows: windowSessionHistory.catalog,
            archive: windowSessionHistory.archive
        )
    }
}
