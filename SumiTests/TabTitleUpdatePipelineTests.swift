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

    func testApplyTitleCandidateIgnoresWhitespace() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Stable Title",
            spaceId: nil,
            index: 0
        )

        let didUpdate = tab.applyTitleCandidate(
            "   ",
            url: URL(string: "https://example.com/watch?v=2")!,
            source: .manual,
            isLoading: false
        )

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(tab.name, "Stable Title")
    }

    func testApplyTitleCandidateAllowsPlaceholderLikeTitleForManualPath() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Stable Title",
            spaceId: nil,
            index: 0
        )

        let didUpdate = tab.applyTitleCandidate(
            "example.com",
            url: URL(string: "https://example.com/watch?v=2")!,
            source: .manual,
            isLoading: true
        )

        XCTAssertTrue(didUpdate)
        XCTAssertEqual(tab.name, "example.com")
    }

    func testApplyTitleCandidateSkipsSameURLAndSameTitle() {
        let url = URL(string: "https://example.com/watch?v=1")!
        let tab = Tab(
            url: url,
            name: "Stable Title",
            spaceId: nil,
            index: 0
        )

        XCTAssertFalse(tab.acceptResolvedDisplayTitle("Stable Title", url: url))

        let didUpdate = tab.applyTitleCandidate(
            "Stable Title",
            url: url,
            source: .manual,
            isLoading: false
        )

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(tab.name, "Stable Title")
    }

    func testApplyTitleCandidateSkipsCrossHostSameTitle() {
        let tab = Tab(
            url: URL(string: "https://example.com/watch?v=1")!,
            name: "Shared Title",
            spaceId: nil,
            index: 0
        )

        let didUpdate = tab.applyTitleCandidate(
            "Shared Title",
            url: URL(string: "https://other.example/watch?v=2")!,
            source: .manual,
            isLoading: false
        )

        XCTAssertFalse(didUpdate)
        XCTAssertEqual(tab.name, "Shared Title")
    }

    func testManualTitleCandidateUsesUnifiedPipeline() {
        let url = URL(string: "https://example.com/watch?v=1")!
        let tab = Tab(
            url: url,
            name: "Initial Title",
            spaceId: nil,
            index: 0
        )

        let didUpdate = tab.applyTitleCandidate(
            "Manual Title",
            url: url,
            source: .manual,
            isLoading: false
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
