import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class RecentlyClosedManagerTests: XCTestCase {
    func testCaptureClosedTabSkipsEmptySurface() {
        let manager = RecentlyClosedManager()
        let emptyTab = Tab(url: SumiSurface.emptyTabURL)

        manager.captureClosedTab(
            emptyTab,
            sourceSpaceId: nil,
            currentURL: emptyTab.url,
            canGoBack: false,
            canGoForward: false
        )

        XCTAssertTrue(manager.items.isEmpty)
    }

    func testMostRecentItemIsPrepended() {
        let manager = RecentlyClosedManager()
        let firstTab = Tab(url: URL(string: "https://example.com")!, name: "Example")
        let secondTab = Tab(url: URL(string: "https://other.com")!, name: "Other")

        manager.captureClosedTab(firstTab, sourceSpaceId: nil, currentURL: firstTab.url, canGoBack: false, canGoForward: false)
        manager.captureClosedTab(secondTab, sourceSpaceId: nil, currentURL: secondTab.url, canGoBack: false, canGoForward: false)

        XCTAssertEqual(manager.items.count, 2)
        guard case .tab(let mostRecentTab)? = manager.mostRecentItem else {
            XCTFail("Expected most recent recently closed item to be a tab")
            return
        }
        XCTAssertEqual(mostRecentTab.title, "Other")
    }

    func testDistinctWindowIdentitiesWithSameSessionRemainDistinct() {
        let manager = RecentlyClosedManager()
        let session = makeSessionRecoveryWindowSession(currentTabId: UUID())
        let firstWindowId = UUID()
        let secondWindowId = UUID()

        manager.captureClosedWindow(
            sessionWindowId: firstWindowId,
            title: "First",
            session: session
        )
        manager.captureClosedWindow(
            sessionWindowId: secondWindowId,
            title: "Second",
            session: session
        )

        XCTAssertEqual(manager.items.count, 2)
        let windowIds = manager.items.compactMap { item -> UUID? in
            guard case .window(let window) = item else { return nil }
            return window.sessionWindowId
        }
        XCTAssertEqual(windowIds, [secondWindowId, firstWindowId])
    }

    func testRepeatedCloseForSameWindowIdentityReplacesEarlierEvent() {
        let manager = RecentlyClosedManager()
        let sessionWindowId = UUID()

        manager.captureClosedWindow(
            sessionWindowId: sessionWindowId,
            title: "Earlier",
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        manager.captureClosedWindow(
            sessionWindowId: sessionWindowId,
            title: "Latest",
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )

        XCTAssertEqual(manager.items.count, 1)
        guard case .window(let window)? = manager.mostRecentItem else {
            return XCTFail("Expected a window history item")
        }
        XCTAssertEqual(window.title, "Latest")
        XCTAssertEqual(window.sessionWindowId, sessionWindowId)
    }
}
