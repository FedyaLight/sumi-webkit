import AppKit
import XCTest

@testable import Sumi

@MainActor
final class WindowSessionReopenServiceTests: XCTestCase {
    func testReopenPublishesPreparedArchivedWindow() async throws {
        let harness = makeHarness()
        defer { harness.closeAllWindows() }
        let snapshot = archivedWindowSnapshot(profileID: UUID())

        let didReopen = await harness.service.reopenWindow(from: snapshot)

        XCTAssertTrue(didReopen)
        let restoredWindow = try XCTUnwrap(
            harness.windows.allWindows.first {
                $0.restorationState.restoredSessionWindowID == snapshot.id
            }
        )
        XCTAssertEqual(restoredWindow.currentProfileId, snapshot.session.currentProfileId)
        XCTAssertFalse(restoredWindow.restorationState.isAwaitingInitialResolution)
    }

    func testReopenDoesNotClaimAnExistingUnrelatedWindow() async throws {
        let harness = makeHarness()
        defer { harness.closeAllWindows() }
        let existingWindow = BrowserWindowState()
        harness.windows.register(existingWindow)
        let snapshot = archivedWindowSnapshot()

        let didReopen = await harness.service.reopenWindow(from: snapshot)

        XCTAssertTrue(didReopen)
        XCTAssertEqual(harness.windows.allWindows.count, 2)
        XCTAssertTrue(harness.windows.allWindows.contains { $0 === existingWindow })
        let restoredWindow = try XCTUnwrap(
            harness.windows.allWindows.first {
                $0.restorationState.restoredSessionWindowID == snapshot.id
            }
        )
        XCTAssertFalse(restoredWindow === existingWindow)
    }

    func testReopenTreatsExistingArchiveIdentityAsAlreadyRestored() async {
        let harness = makeHarness()
        defer { harness.closeAllWindows() }
        let snapshot = archivedWindowSnapshot()
        let existingWindow = BrowserWindowState()
        existingWindow.restorationState.restoredSessionWindowID = snapshot.id
        harness.windows.register(existingWindow)

        let didReopen = await harness.service.reopenWindow(from: snapshot)

        XCTAssertTrue(didReopen)
        XCTAssertEqual(harness.windows.allWindows.count, 1)
        XCTAssertIdentical(harness.windows.allWindows.first, existingWindow)
    }

    func testConcurrentReopensCreateDifferentArchivedWindows() async throws {
        let harness = makeHarness()
        defer { harness.closeAllWindows() }
        let firstSnapshot = archivedWindowSnapshot(currentTabId: UUID())
        let secondSnapshot = archivedWindowSnapshot(currentTabId: UUID())

        let firstTask = Task {
            await harness.service.reopenWindow(from: firstSnapshot)
        }
        let secondTask = Task {
            await harness.service.reopenWindow(from: secondSnapshot)
        }
        let results = await [firstTask.value, secondTask.value]

        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(
            Set(
                harness.windows.allWindows.compactMap(
                    \.restorationState.restoredSessionWindowID
                )
            ),
            Set([firstSnapshot.id, secondSnapshot.id])
        )
    }

    func testConcurrentReopensForSameArchiveIdentityCreateOneWindow() async {
        let harness = makeHarness()
        defer { harness.closeAllWindows() }
        let snapshot = archivedWindowSnapshot(currentTabId: UUID())

        async let first = harness.service.reopenWindow(from: snapshot)
        async let second = harness.service.reopenWindow(from: snapshot)
        let results = await [first, second]

        XCTAssertEqual(results, [true, true])
        XCTAssertEqual(
            harness.windows.allWindows.filter {
                $0.restorationState.restoredSessionWindowID == snapshot.id
            }.count,
            1
        )
    }

    @MainActor
    private struct Harness {
        let browser: BrowserManager
        let windows: WindowRegistry
        let service: WindowSessionReopenService

        func closeAllWindows() {
            for window in windows.allWindows {
                let shell = windows.appKitWindow(for: window)
                _ = windows.discardRejectedRegistration(window)
                shell?.close()
            }
        }
    }

    private func makeHarness() -> Harness {
        let browser = BrowserManager()
        let windows = browser.windowRegistry
        browser.windowShellContentViewFactory = { _, _ in NSView() }
        installWindowRegistryTestEventSink(
            on: windows,
            prepareWindowRegistration: browser.windowSessionBundle
                .restoration.prepareRegistration,
            publishWindowRegistration: browser.windowSessionBundle
                .restoration.commitRegistration
        )
        let service = WindowSessionReopenService(
            windows: windows,
            creation: ArchivedWindowCreationTransaction(
                windows: browser.windowCommands,
                restoration: browser.windowSessionBundle.restoreService
            )
        )
        return Harness(browser: browser, windows: windows, service: service)
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
