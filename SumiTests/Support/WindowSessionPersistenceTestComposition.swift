import Foundation

@testable import Sumi

/// Test-only composition for restore-service suites. It mirrors the production
/// durable-write/coordinator/archive boundary without constructing a browser
/// root.
@MainActor
final class WindowSessionPersistenceTestComposition {
    let coordinator: WindowSessionPersistenceCoordinator
    let lastSessionWindowsStore: LastSessionWindowsStore

    init(
        snapshotStore: WindowSessionSnapshotStore,
        scheduler: WindowSessionPersistenceScheduler,
        snapshotFactory: WindowSessionSnapshotFactory,
        windows: WindowRegistry
    ) {
        let lastSessionWindowsStore = LastSessionWindowsStore()
        let startupRestore = BrowserStartupSessionRestoreOwner(
            lastSessionWindowsStore: lastSessionWindowsStore
        )
        startupRestore.markRestoreOfferConsumed()
        let catalog = OpenWindowSessionCatalog(
            windows: windows,
            snapshots: snapshotFactory
        )
        let archive = LastSessionWindowArchive(
            openWindows: catalog,
            lastSessionWindowsStore: lastSessionWindowsStore,
            startupRestore: startupRestore
        )

        self.lastSessionWindowsStore = lastSessionWindowsStore
        self.coordinator = WindowSessionPersistenceCoordinator(
            snapshotStore: snapshotStore,
            snapshotFactory: snapshotFactory,
            scheduler: scheduler,
            openWindows: catalog,
            archive: archive
        )
    }
}
