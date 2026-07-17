import Foundation

@testable import Sumi

/// Test-only composition for restore-service suites. It mirrors the production
/// durable-write/coordinator/archive boundary without constructing a browser
/// root and removes its isolated archive domain on release.
@MainActor
final class WindowSessionPersistenceTestComposition {
    let coordinator: WindowSessionPersistenceCoordinator
    let lastSessionWindowsStore: LastSessionWindowsStore

    private let userDefaultsSuiteName: String

    init(
        snapshotStore: WindowSessionSnapshotStore,
        scheduler: WindowSessionPersistenceScheduler,
        snapshotFactory: WindowSessionSnapshotFactory,
        windows: WindowRegistry
    ) {
        let suiteName = "WindowSessionPersistenceTestComposition.\(UUID().uuidString)"
        guard let userDefaults = UserDefaults(suiteName: suiteName) else {
            preconditionFailure("Failed to create window-session test defaults")
        }
        userDefaults.removePersistentDomain(forName: suiteName)
        let lastSessionWindowsStore = LastSessionWindowsStore(
            userDefaults: userDefaults
        )
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

        self.userDefaultsSuiteName = suiteName
        self.lastSessionWindowsStore = lastSessionWindowsStore
        self.coordinator = WindowSessionPersistenceCoordinator(
            persistence: WindowSessionPersistenceService(
                store: snapshotStore,
                snapshotFactory: snapshotFactory
            ),
            scheduler: scheduler,
            openWindows: catalog,
            archive: archive
        )
    }

    isolated deinit {
        UserDefaults.standard.removePersistentDomain(
            forName: userDefaultsSuiteName
        )
    }
}
