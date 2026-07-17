import XCTest

@testable import Sumi

@MainActor
final class LastSessionWindowArchiveTests: XCTestCase {
    func testRefreshArchivesCurrentRegularWindowsAndSkipsIncognito() throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowArchiveTests")
        let regularWindow = BrowserWindowState()
        regularWindow.currentTabId = UUID()
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        incognitoWindow.currentTabId = UUID()
        let archive = makeArchive(
            windows: [regularWindow, incognitoWindow],
            store: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )

        archive.refresh(excludingWindowID: nil)

        XCTAssertEqual(
            store.snapshots,
            [snapshot(of: regularWindow)]
        )
    }

    func testRefreshExcludesExactWindowAndKeepsStartupOfferForSingleSurvivor() throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowArchiveTests")
        let closingWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        survivingWindow.currentTabId = UUID()
        let startupRestore = StartupSessionRestoreProviderFake()
        let archive = makeArchive(
            windows: [closingWindow, survivingWindow],
            store: store,
            startupRestore: startupRestore
        )

        archive.refresh(excludingWindowID: closingWindow.id)

        XCTAssertEqual(
            store.snapshots,
            [snapshot(of: survivingWindow)]
        )
        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
    }

    func testRefreshFallsBackToAllWindowsWhenExclusionEmptiesResult() throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowArchiveTests")
        let onlyWindow = BrowserWindowState()
        onlyWindow.currentTabId = UUID()
        let archive = makeArchive(
            windows: [onlyWindow],
            store: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )

        archive.refresh(excludingWindowID: onlyWindow.id)

        XCTAssertEqual(
            store.snapshots,
            [snapshot(of: onlyWindow)]
        )
    }

    func testRefreshMarksStartupOfferConsumedWhenMultipleWindowsRemain() throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowArchiveTests")
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        firstWindow.currentTabId = UUID()
        secondWindow.currentTabId = UUID()
        let startupRestore = StartupSessionRestoreProviderFake()
        let archive = makeArchive(
            windows: [firstWindow, secondWindow],
            store: store,
            startupRestore: startupRestore
        )

        archive.refresh(excludingWindowID: nil)

        XCTAssertEqual(
            store.snapshots,
            [
                snapshot(of: firstWindow),
                snapshot(of: secondWindow),
            ]
        )
        XCTAssertTrue(startupRestore.didConsumeRestoreOffer)
    }

    func testRefreshPreservesStartupArchiveWhileManualRestoreIsOffered() throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowArchiveTests")
        let currentWindow = BrowserWindowState()
        let startupSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let startupTabSnapshot = TabPersistenceSnapshot(
            spaces: [],
            tabs: [],
            folders: [],
            state: TabPersistenceSelection(currentTabID: nil, currentSpaceID: nil)
        )
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: [startupSnapshot],
            tabSnapshot: startupTabSnapshot
        )
        let archive = makeArchive(
            windows: [currentWindow],
            store: store,
            startupRestore: startupRestore
        )

        archive.refresh(excludingWindowID: nil)

        XCTAssertEqual(store.snapshots, [startupSnapshot])
        XCTAssertNotNil(store.tabSnapshot)
        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
    }

    func testRefreshPreservesOfferedArchiveWithoutTabSnapshot() throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "LastSessionWindowArchiveTests"
        )
        let sourceSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let currentWindow = BrowserWindowState()
        let startupRestore = StartupSessionRestoreProviderFake(
            canOfferRestoreShortcut: true,
            windowSnapshots: [sourceSnapshot],
            tabSnapshot: nil
        )
        let archive = makeArchive(
            windows: [currentWindow],
            store: store,
            startupRestore: startupRestore
        )

        archive.refresh(excludingWindowID: nil)

        XCTAssertEqual(store.snapshots, [sourceSnapshot])
        XCTAssertNil(store.tabSnapshot)
        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
    }

    func testArchivedStateReadsBackFromTheStore() throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowArchiveTests")
        let archivedSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let archive = makeArchive(
            windows: [],
            store: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )

        XCTAssertFalse(archive.canRestoreLastSession)
        store.updateSnapshots([archivedSnapshot])
        XCTAssertTrue(archive.canRestoreLastSession)
        XCTAssertEqual(archive.archivedWindowSnapshots, [archivedSnapshot])
        XCTAssertNil(archive.archivedTabSnapshot)
    }

    func testEmptyLiveProjectionDoesNotImplicitlyClearExistingArchive() throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "LastSessionWindowArchiveTests"
        )
        let existingSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots([existingSnapshot])
        let archive = makeArchive(
            windows: [],
            store: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )

        archive.refresh(excludingWindowID: nil)

        XCTAssertEqual(store.snapshots, [existingSnapshot])
    }

    func testUnregisteredSurvivorDoesNotPreventSoleWindowFallback() throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "LastSessionWindowArchiveTests"
        )
        let existingSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots([existingSnapshot])
        let closingWindow = BrowserWindowState()
        closingWindow.currentTabId = UUID()
        let archive = makeArchive(
            windows: [closingWindow],
            store: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )

        archive.refresh(excludingWindowID: closingWindow.id)

        XCTAssertEqual(store.snapshots, [snapshot(of: closingWindow)])
    }

    private func makeArchive(
        windows: [BrowserWindowState],
        store: LastSessionWindowsStore,
        startupRestore: StartupSessionRestoreProviderFake
    ) -> LastSessionWindowArchive {
        let registry = WindowRegistry()
        windows.forEach { window in
            _ = registry.register(window)
        }
        return LastSessionWindowArchive(
            openWindows: OpenWindowSessionCatalog(
                windows: registry,
                snapshots: snapshotFactory
            ),
            lastSessionWindowsStore: store,
            startupRestore: startupRestore
        )
    }

    private var snapshotFactory: WindowSessionSnapshotFactory {
        WindowSessionSnapshotFactory(glanceManager: GlanceManager())
    }

    private func snapshot(of window: BrowserWindowState) -> LastSessionWindowSnapshot {
        LastSessionWindowSnapshot(
            id: window.restorationState.restoredSessionWindowID ?? window.id,
            session: snapshotFactory.make(for: window)
        )
    }
}
