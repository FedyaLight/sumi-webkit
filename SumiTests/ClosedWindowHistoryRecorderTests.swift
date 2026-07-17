import XCTest

@testable import Sumi

@MainActor
final class ClosedWindowHistoryRecorderTests: XCTestCase {
    func testMeaningfulRegularWindowIsRecordedWithResolvedTitleAndExactSnapshot() {
        let browser = BrowserManager()
        let recentlyClosed = RecentlyClosedManager()
        let closingWindow = BrowserWindowState()
        let restoredSessionWindowId = UUID()
        closingWindow.restorationState.restoredSessionWindowID = restoredSessionWindowId
        let space = installTestSpace(
            in: browser.spaceStateOwner,
            name: "Closed Window Space"
        )
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://closed.example",
            in: space,
            activate: false
        )
        tab.name = "Closed Window"
        closingWindow.currentSpaceId = space.id
        closingWindow.currentTabId = tab.id
        let recorder = makeRecorder(
            browser: browser,
            recentlyClosed: recentlyClosed
        )

        recorder.recordWindowWillClose(closingWindow)

        guard case .window(let closedItem)? = recentlyClosed.items.first else {
            return XCTFail("Expected the closed regular window to be captured")
        }
        XCTAssertEqual(closedItem.sessionWindowId, restoredSessionWindowId)
        XCTAssertNotEqual(closedItem.id, restoredSessionWindowId)
        XCTAssertEqual(closedItem.title, "Closed Window")
        XCTAssertEqual(
            closedItem.session,
            WindowSessionSnapshotFactory(
                glanceManager: browser.glanceManager
            ).make(for: closingWindow)
        )
    }

    func testFullyEmptyWindowIsNotRecorded() {
        let recentlyClosed = RecentlyClosedManager()
        let emptyWindow = BrowserWindowState()
        emptyWindow.isShowingEmptyState = true
        let recorder = makeRecorder(
            browser: BrowserManager(),
            recentlyClosed: recentlyClosed
        )

        recorder.recordWindowWillClose(emptyWindow)

        XCTAssertTrue(recentlyClosed.items.isEmpty)
    }

    func testIncognitoWindowIsNotRecorded() {
        let recentlyClosed = RecentlyClosedManager()
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        incognitoWindow.currentTabId = UUID()
        let recorder = makeRecorder(
            browser: BrowserManager(),
            recentlyClosed: recentlyClosed
        )

        recorder.recordWindowWillClose(incognitoWindow)

        XCTAssertTrue(recentlyClosed.items.isEmpty)
    }

    func testRestoredArchiveIdentityIsNotReplacedByRuntimeWindowID() {
        let browser = BrowserManager()
        let recentlyClosed = RecentlyClosedManager()
        let window = BrowserWindowState()
        let archiveID = UUID()
        window.restorationState.restoredSessionWindowID = archiveID
        window.currentTabId = UUID()
        let recorder = makeRecorder(
            browser: browser,
            recentlyClosed: recentlyClosed
        )

        recorder.recordWindowWillClose(window)

        guard case .window(let closedItem)? = recentlyClosed.items.first else {
            return XCTFail("Expected restored window history")
        }
        XCTAssertEqual(closedItem.sessionWindowId, archiveID)
        XCTAssertNotEqual(closedItem.sessionWindowId, window.id)
    }

    private func makeRecorder(
        browser: BrowserManager,
        recentlyClosed: RecentlyClosedManager
    ) -> ClosedWindowHistoryRecorder {
        ClosedWindowHistoryRecorder(
            snapshots: WindowSessionSnapshotFactory(
                glanceManager: browser.glanceManager
            ),
            titles: ClosedWindowDisplayTitleProjection(
                windowTabs: browser.windowTabContext,
                spaces: browser.spaceStateOwner
            ),
            recentlyClosedManager: recentlyClosed
        )
    }
}
