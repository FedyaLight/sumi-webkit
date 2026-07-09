//
//  TopLinkSuggestionOwnerTests.swift
//  SumiTests
//
//

import XCTest

@testable import Sumi

@MainActor
final class TopLinkSuggestionOwnerTests: XCTestCase {
    func testOrdersTopSitesBeforeBookmarksBeforeOpenTabs() async {
        let historyEntry = makeHistoryEntry(url: "https://top-site.example", title: "Top Site")
        let bookmark = SumiBookmark(id: "bm", title: "Bookmarked", url: URL(string: "https://bookmarked.example")!, folderID: nil)
        let tab = Tab(url: URL(string: "https://open-tab.example")!)
        tab.name = "Open Tab"

        let owner = TopLinkSuggestionOwner(
            topVisitedSites: { _ in [historyEntry] },
            bookmarks: { [bookmark] },
            openTabs: { [tab] }
        )

        let suggestions = await owner.suggestions(limit: 5)

        XCTAssertEqual(suggestions.map(\.text), ["Top Site", "Bookmarked", "Open Tab"])
    }

    func testDeduplicatesAcrossSourcesByCanonicalURL() async {
        let sharedURL = "https://shared.example"
        let historyEntry = makeHistoryEntry(url: sharedURL, title: "From History")
        let bookmark = SumiBookmark(id: "bm", title: "From Bookmark", url: URL(string: sharedURL)!, folderID: nil)

        let owner = TopLinkSuggestionOwner(
            topVisitedSites: { _ in [historyEntry] },
            bookmarks: { [bookmark] },
            openTabs: { [] }
        )

        let suggestions = await owner.suggestions(limit: 5)

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.text, "From History")
    }

    func testRespectsLimitAcrossCombinedSources() async {
        let entries = (0..<5).map { makeHistoryEntry(url: "https://site\($0).example", title: "Site \($0)") }

        let owner = TopLinkSuggestionOwner(
            topVisitedSites: { _ in entries },
            bookmarks: { [] },
            openTabs: { [] }
        )

        let suggestions = await owner.suggestions(limit: 2)

        XCTAssertEqual(suggestions.count, 2)
    }

    private func makeHistoryEntry(url: String, title: String) -> HistoryListItem {
        HistoryListItem(
            id: url,
            visitID: nil,
            url: URL(string: url)!,
            title: title,
            domain: "example.com",
            siteDomain: "example.com",
            visitedAt: Date(),
            timeText: "",
            visitCount: 1,
            isSiteAggregate: true
        )
    }
}
