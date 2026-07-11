import XCTest

@testable import Sumi

@MainActor
final class WindowSessionReopenServiceTests: XCTestCase {
    func testReopenPublishesPreparedArchivedWindow() async {
        let windowRegistry = WindowRegistry()
        let existingWindow = BrowserWindowState()
        windowRegistry.register(existingWindow)
        let restoredWindow = BrowserWindowState()
        let snapshot = archivedWindowSnapshot(profileID: UUID())
        var events: [String] = []
        var registeredProfileID: UUID?
        windowRegistry.onWindowRegister = { windowState in
            events.append("register")
            registeredProfileID = windowState.currentProfileId
        }

        let service = WindowSessionReopenService(
            windowRegistry: { windowRegistry },
            createRestoredWindow: { receivedSnapshot in
                events.append("prepare")
                restoredWindow.restoredSessionWindowId = receivedSnapshot.id
                restoredWindow.currentProfileId = receivedSnapshot
                    .session.currentProfileId
                restoredWindow.isAwaitingInitialSessionResolution = false
                windowRegistry.register(restoredWindow)
                return restoredWindow
            }
        )

        let didReopen = await service.reopenWindow(from: snapshot)

        XCTAssertTrue(didReopen)
        XCTAssertEqual(events, ["prepare", "register"])
        XCTAssertEqual(registeredProfileID, snapshot.session.currentProfileId)
        XCTAssertEqual(restoredWindow.restoredSessionWindowId, snapshot.id)
    }

    func testReopenDoesNotClaimAnExistingWindow() async {
        let windowRegistry = WindowRegistry()
        let existingWindow = BrowserWindowState()
        windowRegistry.register(existingWindow)
        let restoredWindow = BrowserWindowState()
        var createdWindow: BrowserWindowState?

        let service = WindowSessionReopenService(
            windowRegistry: { windowRegistry },
            createRestoredWindow: { snapshot in
                restoredWindow.restoredSessionWindowId = snapshot.id
                restoredWindow.isAwaitingInitialSessionResolution = false
                createdWindow = restoredWindow
                windowRegistry.register(restoredWindow)
                return restoredWindow
            }
        )

        let didReopen = await service.reopenWindow(
            from: archivedWindowSnapshot()
        )

        XCTAssertTrue(didReopen)
        XCTAssertIdentical(createdWindow, restoredWindow)
        XCTAssertNotIdentical(createdWindow, existingWindow)
    }

    func testReopenReportsFailureWhenNoWindowRegistryIsAvailable() async {
        var didCreateWindow = false
        let service = WindowSessionReopenService(
            windowRegistry: { nil },
            createRestoredWindow: { _ in
                didCreateWindow = true
                return BrowserWindowState()
            }
        )

        let didReopen = await service.reopenWindow(
            from: archivedWindowSnapshot()
        )

        XCTAssertFalse(didReopen)
        XCTAssertFalse(didCreateWindow)
    }

    func testConcurrentReopensCreateDifferentPreparedWindowsInOrder() async {
        let windowRegistry = WindowRegistry()
        let windows = [BrowserWindowState(), BrowserWindowState()]
        let firstSnapshot = archivedWindowSnapshot(currentTabId: UUID())
        let secondSnapshot = archivedWindowSnapshot(currentTabId: UUID())
        var nextWindowIndex = 0
        var prepared: [(LastSessionWindowSnapshot, BrowserWindowState)] = []
        let service = WindowSessionReopenService(
            windowRegistry: { windowRegistry },
            createRestoredWindow: { snapshot in
                let window = windows[nextWindowIndex]
                nextWindowIndex += 1
                window.restoredSessionWindowId = snapshot.id
                window.isAwaitingInitialSessionResolution = false
                prepared.append((snapshot, window))
                windowRegistry.register(window)
                return window
            }
        )

        let firstTask = Task {
            await service.reopenWindow(from: firstSnapshot)
        }
        let secondTask = Task {
            await service.reopenWindow(from: secondSnapshot)
        }
        let results = await [firstTask.value, secondTask.value]

        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(
            prepared.map(\.0.session),
            [firstSnapshot.session, secondSnapshot.session]
        )
        XCTAssertIdentical(prepared[0].1, windows[0])
        XCTAssertIdentical(prepared[1].1, windows[1])
    }

    func testConcurrentReopensForSameArchiveIdentityCreateOneWindow() async {
        let windowRegistry = WindowRegistry()
        let restoredWindow = BrowserWindowState()
        let snapshot = archivedWindowSnapshot(currentTabId: UUID())
        var creationCount = 0
        let service = WindowSessionReopenService(
            windowRegistry: { windowRegistry },
            createRestoredWindow: { receivedSnapshot in
                creationCount += 1
                restoredWindow.restoredSessionWindowId = receivedSnapshot.id
                restoredWindow.isAwaitingInitialSessionResolution = false
                windowRegistry.register(restoredWindow)
                return restoredWindow
            }
        )

        async let first = service.reopenWindow(from: snapshot)
        async let second = service.reopenWindow(from: snapshot)
        let results = await [first, second]

        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(creationCount, 1)
        XCTAssertEqual(restoredWindow.restoredSessionWindowId, snapshot.id)
    }

    func testReopenRejectsUnregisteredPreparedState() async {
        let windowRegistry = WindowRegistry()
        let unregisteredWindow = BrowserWindowState()
        let service = WindowSessionReopenService(
            windowRegistry: { windowRegistry },
            createRestoredWindow: { snapshot in
                unregisteredWindow.restoredSessionWindowId = snapshot.id
                return unregisteredWindow
            }
        )

        let didReopen = await service.reopenWindow(
            from: archivedWindowSnapshot()
        )

        XCTAssertFalse(didReopen)
        XCTAssertTrue(windowRegistry.windows.isEmpty)
    }

    func testReopenRejectsRegisteredStateWithWrongArchiveIdentity() async {
        let windowRegistry = WindowRegistry()
        let wrongWindow = BrowserWindowState()
        let service = WindowSessionReopenService(
            windowRegistry: { windowRegistry },
            createRestoredWindow: { _ in
                wrongWindow.restoredSessionWindowId = UUID()
                wrongWindow.isAwaitingInitialSessionResolution = false
                windowRegistry.register(wrongWindow)
                return wrongWindow
            }
        )

        let didReopen = await service.reopenWindow(
            from: archivedWindowSnapshot()
        )

        XCTAssertFalse(didReopen)
    }

    private func archivedWindowSnapshot(
        currentTabId: UUID? = nil,
        profileID: UUID? = nil
    ) -> LastSessionWindowSnapshot {
        var session = makeSessionRecoveryWindowSession(
            currentTabId: currentTabId
        )
        session.currentProfileId = profileID
        return LastSessionWindowSnapshot(id: UUID(), session: session)
    }
}
