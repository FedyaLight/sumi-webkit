import XCTest
@testable import Sumi

@MainActor
final class TabTitleUpdatePipelineTests: XCTestCase {
    func testHandleSameDocumentNavigationUpdatesOnlyURL() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Original Title",
            spaceId: nil,
            index: 0
        )

        tab.handleSameDocumentNavigation(to: URL(string: "https://example.com/watch?v=2")!)

        XCTAssertEqual(tab.name, "Original Title")
        XCTAssertEqual(tab.url.absoluteString, "https://example.com/watch?v=2")
    }

    func testHandleSameDocumentNavigationUpdatesURLWithoutJavaScriptBridge() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Original Title",
            spaceId: nil,
            index: 0
        )

        tab.handleSameDocumentNavigation(
            to: URL(string: "https://example.com/watch?v=2")!
        )

        XCTAssertEqual(tab.url.absoluteString, "https://example.com/watch?v=2")
        XCTAssertEqual(tab.name, "Original Title")
    }

    func testManualTitleCandidateUpdatesTitleAfterSameDocumentNavigation() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Launcher Title",
            spaceId: nil,
            index: 0
        )

        XCTAssertTrue(tab.acceptResolvedDisplayTitle("Updated Video Title"))
        XCTAssertEqual(tab.name, "Updated Video Title")
    }

    func testAcceptResolvedDisplayTitleIgnoresWhitespace() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Stable Title",
            spaceId: nil,
            index: 0
        )

        let didUpdate = tab.acceptResolvedDisplayTitle("   ")

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(tab.name, "Stable Title")
    }

    func testAcceptResolvedDisplayTitleAllowsPlaceholderLikeTitle() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Stable Title",
            spaceId: nil,
            index: 0
        )

        let didUpdate = tab.acceptResolvedDisplayTitle("example.com")

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(tab.name, "example.com")
    }

    func testAcceptResolvedDisplayTitleSkipsSameURLAndSameTitle() {
        let url = URL(string: "https://example.com/watch?v=1")!
        let tab = Tab(
            url: url,
            name: "Stable Title",
            spaceId: nil,
            index: 0
        )

        XCTAssertFalse(tab.acceptResolvedDisplayTitle("Stable Title", url: url))

        XCTAssertEqual(tab.name, "Stable Title")
    }

    func testAcceptResolvedDisplayTitleSkipsCrossHostSameTitle() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Shared Title",
            spaceId: nil,
            index: 0
        )

        let didUpdate = tab.acceptResolvedDisplayTitle(
            "Shared Title",
            url: URL(string: "https://other.example/watch?v=2")!
        )

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(tab.name, "Shared Title")
    }

    func testAcceptResolvedDisplayTitleUpdatesTitle() {
        let url = URL(string: "https://example.com/watch?v=1")!
        let tab = Tab(
            url: url,
            name: "Initial Title",
            spaceId: nil,
            index: 0
        )

        let didUpdate = tab.acceptResolvedDisplayTitle(
            "Manual Title",
            url: url
        )

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(tab.name, "Manual Title")
    }

    func testNavigationHistoryDisplayTitlePrefersCachedTabTitle() {
        let resolved = NavigationHistoryDisplayTitle.resolve(
            cachedTitle: "Cached Title",
            rawTitle: "Raw Title",
            url: URL(string: "https://example.com/path")!
        )

        XCTAssertEqual(resolved, "Cached Title")
    }

    func testNavigationHistoryDisplayTitleFallsBackToRawTitleThenHost() {
        let withRawTitle = NavigationHistoryDisplayTitle.resolve(
            cachedTitle: "   ",
            rawTitle: "Raw Title",
            url: URL(string: "https://example.com/path")!
        )
        XCTAssertEqual(withRawTitle, "Raw Title")

        let withHost = NavigationHistoryDisplayTitle.resolve(
            cachedTitle: nil,
            rawTitle: "   ",
            url: URL(string: "https://example.com/path")!
        )
        XCTAssertEqual(withHost, "example.com")
    }

    func testBackForwardNavigationSettleDecisionSkipsCancelledGesture() {
        let originURL = URL(string: "https://example.com/watch?v=1")!

        XCTAssertFalse(
            BackForwardNavigationSettleDecision.shouldApplyDeferredActions(
                originURL: originURL,
                originHistoryURL: originURL,
                originHistoryItem: nil,
                currentURL: originURL,
                currentHistoryURL: originURL,
                currentHistoryItem: nil
            )
        )
    }

    func testBackForwardNavigationSettleDecisionAppliesForSuccessfulHistoryMove() {
        let originURL = URL(string: "https://example.com/watch?v=1")!
        let targetURL = URL(string: "https://example.com/watch?v=2")!

        XCTAssertTrue(
            BackForwardNavigationSettleDecision.shouldApplyDeferredActions(
                originURL: originURL,
                originHistoryURL: originURL,
                originHistoryItem: nil,
                currentURL: targetURL,
                currentHistoryURL: targetURL,
                currentHistoryItem: nil
            )
        )
    }
}
