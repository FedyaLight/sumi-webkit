import XCTest

@testable import Sumi

@MainActor
final class LastSessionWindowArchiveTests: XCTestCase {
    func testRefreshArchivesCurrentRegularWindowsAndSkipsIncognito() throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowArchiveTests")
        let regularWindow = BrowserWindowState()
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        let regularSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let archive = makeArchive(
            windows: [regularWindow, incognitoWindow],
            sessions: [
                regularWindow.id: regularSession,
                incognitoWindow.id: makeSessionRecoveryWindowSession(currentTabId: UUID()),
            ],
            store: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )

        archive.refresh(excludingWindowID: nil)

        XCTAssertEqual(
            store.snapshots,
            [LastSessionWindowSnapshot(id: regularWindow.id, session: regularSession)]
        )
    }

    func testRefreshExcludesExactWindowAndKeepsStartupOfferForSingleSurvivor() throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowArchiveTests")
        let closingWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        let survivingSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let startupRestore = StartupSessionRestoreProviderFake()
        let archive = makeArchive(
            windows: [closingWindow, survivingWindow],
            sessions: [
                closingWindow.id: makeSessionRecoveryWindowSession(currentTabId: UUID()),
                survivingWindow.id: survivingSession,
            ],
            store: store,
            startupRestore: startupRestore
        )

        archive.refresh(excludingWindowID: closingWindow.id)

        XCTAssertEqual(
            store.snapshots,
            [LastSessionWindowSnapshot(id: survivingWindow.id, session: survivingSession)]
        )
        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
    }

    func testRefreshFallsBackToAllWindowsWhenExclusionEmptiesResult() throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowArchiveTests")
        let onlyWindow = BrowserWindowState()
        let onlySession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let archive = makeArchive(
            windows: [onlyWindow],
            sessions: [onlyWindow.id: onlySession],
            store: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )

        archive.refresh(excludingWindowID: onlyWindow.id)

        XCTAssertEqual(
            store.snapshots,
            [LastSessionWindowSnapshot(id: onlyWindow.id, session: onlySession)]
        )
    }

    func testRefreshMarksStartupOfferConsumedWhenMultipleWindowsRemain() throws {
        let store = try makeIsolatedLastSessionWindowsStore(suitePrefix: "LastSessionWindowArchiveTests")
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let firstSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let secondSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let startupRestore = StartupSessionRestoreProviderFake()
        let archive = makeArchive(
            windows: [firstWindow, secondWindow],
            sessions: [
                firstWindow.id: firstSession,
                secondWindow.id: secondSession,
            ],
            store: store,
            startupRestore: startupRestore
        )

        archive.refresh(excludingWindowID: nil)

        XCTAssertEqual(
            store.snapshots,
            [
                LastSessionWindowSnapshot(id: firstWindow.id, session: firstSession),
                LastSessionWindowSnapshot(id: secondWindow.id, session: secondSession),
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
            sessions: [currentWindow.id: makeSessionRecoveryWindowSession(currentTabId: UUID())],
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
            sessions: [
                currentWindow.id: makeSessionRecoveryWindowSession(
                    currentTabId: UUID()
                ),
            ],
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
            sessions: [:],
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
            sessions: [:],
            store: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )

        archive.refresh(excludingWindowID: nil)

        XCTAssertEqual(store.snapshots, [existingSnapshot])
    }

    func testMissingSurvivorProjectionDoesNotArchiveClosingWindow() throws {
        let store = try makeIsolatedLastSessionWindowsStore(
            suitePrefix: "LastSessionWindowArchiveTests"
        )
        let existingSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        store.updateSnapshots([existingSnapshot])
        let closingWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        let closingSession = makeSessionRecoveryWindowSession(
            currentTabId: UUID()
        )
        let archive = makeArchive(
            windows: [closingWindow, survivingWindow],
            sessions: [closingWindow.id: closingSession],
            store: store,
            startupRestore: StartupSessionRestoreProviderFake()
        )

        archive.refresh(excludingWindowID: closingWindow.id)

        XCTAssertEqual(store.snapshots, [existingSnapshot])
    }

    private func makeArchive(
        windows: [BrowserWindowState],
        sessions: [UUID: WindowSessionSnapshot],
        store: LastSessionWindowsStore,
        startupRestore: StartupSessionRestoreProviderFake
    ) -> LastSessionWindowArchive {
        LastSessionWindowArchive(
            openWindows: OpenWindowSessionCatalog(
                allWindows: { windows },
                makeWindowSessionSnapshot: { sessions[$0.id] }
            ),
            lastSessionWindowsStore: { store },
            startupRestore: startupRestore
        )
    }
}
