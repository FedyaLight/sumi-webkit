import XCTest

@testable import Sumi

@MainActor
final class OpenWindowSessionCatalogTests: XCTestCase {
    func testRegularWindowSnapshotsFilterIncognitoWindows() {
        let regularWindow = BrowserWindowState()
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        let regularSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let sessions = [
            regularWindow.id: regularSession,
            incognitoWindow.id: makeSessionRecoveryWindowSession(currentTabId: UUID()),
        ]
        let catalog = makeCatalog(
            windows: [regularWindow, incognitoWindow],
            sessions: sessions
        )

        XCTAssertEqual(
            catalog.regularWindowSnapshots(excludingWindowID: nil),
            [LastSessionWindowSnapshot(id: regularWindow.id, session: regularSession)]
        )
    }

    func testRegularWindowSnapshotsExcludeExactWindowID() {
        let excludedWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        let survivingSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let sessions = [
            excludedWindow.id: makeSessionRecoveryWindowSession(currentTabId: UUID()),
            survivingWindow.id: survivingSession,
        ]
        let catalog = makeCatalog(
            windows: [excludedWindow, survivingWindow],
            sessions: sessions
        )

        XCTAssertEqual(
            catalog.regularWindowSnapshots(excludingWindowID: excludedWindow.id),
            [LastSessionWindowSnapshot(id: survivingWindow.id, session: survivingSession)]
        )
    }

    func testRegularWindowSnapshotsMapEveryWindowToItsExactSession() {
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let firstSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let secondSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let catalog = makeCatalog(
            windows: [firstWindow, secondWindow],
            sessions: [
                firstWindow.id: firstSession,
                secondWindow.id: secondSession,
            ]
        )

        XCTAssertEqual(
            catalog.regularWindowSnapshots(excludingWindowID: nil),
            [
                LastSessionWindowSnapshot(id: firstWindow.id, session: firstSession),
                LastSessionWindowSnapshot(id: secondWindow.id, session: secondSession),
            ]
        )
    }

    func testWindowWithoutSnapshotProducesNoElement() {
        let mappableWindow = BrowserWindowState()
        let unmappableWindow = BrowserWindowState()
        let mappableSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let catalog = makeCatalog(
            windows: [mappableWindow, unmappableWindow],
            sessions: [mappableWindow.id: mappableSession]
        )

        XCTAssertEqual(
            catalog.regularWindowSnapshots(excludingWindowID: nil),
            [LastSessionWindowSnapshot(id: mappableWindow.id, session: mappableSession)]
        )
        XCTAssertNil(catalog.snapshot(of: unmappableWindow))
        XCTAssertEqual(catalog.snapshot(of: mappableWindow), mappableSession)
    }

    func testRestoredWindowPublishesStableArchiveIdentityAfterSessionMutation() {
        let archivedWindowID = UUID()
        let restoredWindow = BrowserWindowState()
        restoredWindow.restorationState.restoredSessionWindowID = archivedWindowID
        let mutatedSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let catalog = makeCatalog(
            windows: [restoredWindow],
            sessions: [restoredWindow.id: mutatedSession]
        )

        XCTAssertEqual(
            catalog.regularWindowSnapshots(excludingWindowID: nil),
            [LastSessionWindowSnapshot(id: archivedWindowID, session: mutatedSession)]
        )
    }

    func testDurablePrimarySelectionIsDeterministicAndSkipsIncognito() throws {
        let excludedWindow = BrowserWindowState(
            id: try XCTUnwrap(UUID(uuidString: "FFFFFFFF-FFFF-FFFF-FFFF-FFFFFFFFFFFF"))
        )
        let expectedWindow = BrowserWindowState(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000001"))
        )
        let laterWindow = BrowserWindowState(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000002"))
        )
        let incognitoWindow = BrowserWindowState(
            id: try XCTUnwrap(UUID(uuidString: "00000000-0000-0000-0000-000000000000"))
        )
        incognitoWindow.isIncognito = true
        let catalog = makeCatalog(
            windows: [laterWindow, incognitoWindow, excludedWindow, expectedWindow],
            sessions: [:]
        )

        XCTAssertIdentical(
            catalog.deterministicRegularWindow(
                excludingWindowID: excludedWindow.id
            ),
            expectedWindow
        )
    }

    private func makeCatalog(
        windows: [BrowserWindowState],
        sessions: [UUID: WindowSessionSnapshot]
    ) -> OpenWindowSessionCatalog {
        OpenWindowSessionCatalog(
            allWindows: { windows },
            makeWindowSessionSnapshot: { sessions[$0.id] }
        )
    }
}
