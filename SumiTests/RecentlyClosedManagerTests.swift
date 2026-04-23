import XCTest

@testable import Sumi

@MainActor
final class RecentlyClosedManagerTests: XCTestCase {
    func testCaptureClosedTabSkipsEmptySurface() {
        let manager = RecentlyClosedManager()
        let emptyTab = Tab(url: SumiSurface.emptyTabURL, skipFaviconFetch: true)

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
        let firstTab = Tab(url: URL(string: "https://example.com")!, name: "Example", skipFaviconFetch: true)
        let secondTab = Tab(url: URL(string: "https://other.com")!, name: "Other", skipFaviconFetch: true)

        manager.captureClosedTab(firstTab, sourceSpaceId: nil, currentURL: firstTab.url, canGoBack: false, canGoForward: false)
        manager.captureClosedTab(secondTab, sourceSpaceId: nil, currentURL: secondTab.url, canGoBack: false, canGoForward: false)

        XCTAssertEqual(manager.items.count, 2)
        guard case .tab(let mostRecentTab)? = manager.mostRecentItem else {
            XCTFail("Expected most recent recently closed item to be a tab")
            return
        }
        XCTAssertEqual(mostRecentTab.title, "Other")
    }
}
