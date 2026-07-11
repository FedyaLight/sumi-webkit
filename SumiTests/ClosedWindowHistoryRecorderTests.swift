import XCTest

@testable import Sumi

@MainActor
final class ClosedWindowHistoryRecorderTests: XCTestCase {
    func testMeaningfulRegularWindowIsRecordedWithResolvedTitleAndExactSnapshot() {
        let recentlyClosed = RecentlyClosedManager()
        let closingWindow = BrowserWindowState()
        let restoredSessionWindowId = UUID()
        closingWindow.restoredSessionWindowId = restoredSessionWindowId
        let closingSession = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let recorder = makeRecorder(
            sessions: [closingWindow.id: closingSession],
            title: { windowState in
                windowState.id == closingWindow.id ? "Closed Window" : "Other"
            },
            recentlyClosed: recentlyClosed
        )

        recorder.recordWindowWillClose(closingWindow)

        guard case .window(let closedItem)? = recentlyClosed.items.first else {
            return XCTFail("Expected the closed regular window to be captured")
        }
        XCTAssertEqual(closedItem.sessionWindowId, restoredSessionWindowId)
        XCTAssertNotEqual(closedItem.id, restoredSessionWindowId)
        XCTAssertEqual(closedItem.title, "Closed Window")
        XCTAssertEqual(closedItem.session, closingSession)
    }

    func testFullyEmptyWindowIsNotRecorded() {
        let recentlyClosed = RecentlyClosedManager()
        let emptyWindow = BrowserWindowState()
        let emptySession = makeSessionRecoveryWindowSession(
            currentTabId: nil,
            isShowingEmptyState: true
        )
        let recorder = makeRecorder(
            sessions: [emptyWindow.id: emptySession],
            recentlyClosed: recentlyClosed
        )

        recorder.recordWindowWillClose(emptyWindow)

        XCTAssertTrue(recentlyClosed.items.isEmpty)
    }

    func testIncognitoWindowIsNotRecorded() {
        let recentlyClosed = RecentlyClosedManager()
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        let recorder = makeRecorder(
            sessions: [
                incognitoWindow.id: makeSessionRecoveryWindowSession(currentTabId: UUID()),
            ],
            recentlyClosed: recentlyClosed
        )

        recorder.recordWindowWillClose(incognitoWindow)

        XCTAssertTrue(recentlyClosed.items.isEmpty)
    }

    func testMissingSnapshotDoesNotCreateHistoryItem() {
        let recentlyClosed = RecentlyClosedManager()
        let unmappableWindow = BrowserWindowState()
        let recorder = makeRecorder(
            sessions: [:],
            recentlyClosed: recentlyClosed
        )

        recorder.recordWindowWillClose(unmappableWindow)

        XCTAssertTrue(recentlyClosed.items.isEmpty)
    }

    private func makeRecorder(
        sessions: [UUID: WindowSessionSnapshot],
        title: @escaping @MainActor (BrowserWindowState) -> String = { _ in "Window" },
        recentlyClosed: RecentlyClosedManager
    ) -> ClosedWindowHistoryRecorder {
        ClosedWindowHistoryRecorder(
            openWindows: OpenWindowSessionCatalog(
                allWindows: { [] },
                makeWindowSessionSnapshot: { sessions[$0.id] }
            ),
            windowDisplayTitle: title,
            recentlyClosedManager: { recentlyClosed }
        )
    }
}
