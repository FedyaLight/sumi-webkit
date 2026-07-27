import XCTest

@testable import Sumi

@MainActor
final class OpenWindowSessionCatalogTests: XCTestCase {
    func testRegularWindowSnapshotsFilterIncognitoWindows() {
        let regularWindow = BrowserWindowState()
        regularWindow.currentTabId = UUID()
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        incognitoWindow.currentTabId = UUID()
        let catalog = makeCatalog(windows: [regularWindow, incognitoWindow])

        XCTAssertEqual(
            catalog.regularWindowSnapshots(excludingWindowID: nil),
            [snapshot(of: regularWindow)]
        )
    }

    func testRegularWindowSnapshotsExcludeExactWindowID() {
        let excludedWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        survivingWindow.currentTabId = UUID()
        let catalog = makeCatalog(windows: [excludedWindow, survivingWindow])

        XCTAssertEqual(
            catalog.regularWindowSnapshots(excludingWindowID: excludedWindow.id),
            [snapshot(of: survivingWindow)]
        )
    }

    func testRegularWindowSnapshotsMapEveryWindowToItsExactSession() {
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        firstWindow.currentTabId = UUID()
        secondWindow.currentSpaceId = UUID()
        let catalog = makeCatalog(windows: [firstWindow, secondWindow])

        XCTAssertEqual(
            catalog.regularWindowSnapshots(excludingWindowID: nil),
            [
                snapshot(of: firstWindow),
                snapshot(of: secondWindow),
            ]
        )
    }

    func testContainsRegularWindowRequiresExactRegisteredIdentity() {
        let registeredWindow = BrowserWindowState()
        let staleSameIDWindow = BrowserWindowState(id: registeredWindow.id)
        let catalog = makeCatalog(windows: [registeredWindow])

        XCTAssertTrue(catalog.containsRegularWindow(registeredWindow))
        XCTAssertFalse(catalog.containsRegularWindow(staleSameIDWindow))
    }

    func testRestoredWindowPublishesStableArchiveIdentityAfterSessionMutation() {
        let archivedWindowID = UUID()
        let restoredWindow = BrowserWindowState()
        restoredWindow.restorationState.restoredSessionWindowID = archivedWindowID
        restoredWindow.currentTabId = UUID()
        let catalog = makeCatalog(windows: [restoredWindow])

        XCTAssertEqual(
            catalog.regularWindowSnapshots(excludingWindowID: nil),
            [
                LastSessionWindowSnapshot(
                    id: archivedWindowID,
                    session: snapshotFactory.make(for: restoredWindow)
                ),
            ]
        )
    }

    func testRegularWindowIDsDoNotBuildSessionSnapshots() {
        let restoredID = UUID()
        let regularWindow = BrowserWindowState()
        regularWindow.restorationState.restoredSessionWindowID = restoredID
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        let registry = WindowRegistry()
        registry.register(regularWindow)
        registry.register(incognitoWindow)
        var geometryProjectionCount = 0
        let catalog = OpenWindowSessionCatalog(
            windows: registry,
            snapshots: WindowSessionSnapshotFactory(
                glanceManager: GlanceManager(),
                windowGeometry: { _ in
                    geometryProjectionCount += 1
                    return nil
                }
            )
        )

        XCTAssertEqual(catalog.regularWindowIDs(), [restoredID])
        XCTAssertEqual(geometryProjectionCount, 0)
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
            windows: [laterWindow, incognitoWindow, excludedWindow, expectedWindow]
        )

        XCTAssertIdentical(
            catalog.deterministicRegularWindow(
                excludingWindowID: excludedWindow.id
            ),
            expectedWindow
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

    private func makeCatalog(windows: [BrowserWindowState]) -> OpenWindowSessionCatalog {
        let registry = WindowRegistry()
        windows.forEach { window in
            _ = registry.register(window)
        }
        return OpenWindowSessionCatalog(
            windows: registry,
            snapshots: snapshotFactory
        )
    }
}
