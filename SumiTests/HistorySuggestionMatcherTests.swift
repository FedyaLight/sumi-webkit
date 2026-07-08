//
//  HistorySuggestionMatcherTests.swift
//  SumiTests
//
//

import XCTest

@testable import Sumi

@MainActor
final class HistorySuggestionMatcherTests: XCTestCase {
    // MARK: - merge

    func testMergePrefersSiteMatchesOverVisitMatchesForSameURL() {
        let url = URL(string: "https://example.com/page")!
        let siteEntry = makeEntry(id: "site", url: url, title: "Site Aggregate", isSiteAggregate: true)
        let visitEntry = makeEntry(id: "visit", url: url, title: "Individual Visit", isSiteAggregate: false)

        let merged = HistorySuggestionMatcher.merge(siteMatches: [siteEntry], visitMatches: [visitEntry])

        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(merged.first?.id, "site")
    }

    func testMergeKeepsDistinctURLsFromBothSources() {
        let siteEntry = makeEntry(id: "site", url: URL(string: "https://example.com/a")!, title: "A")
        let visitEntry = makeEntry(id: "visit", url: URL(string: "https://example.com/b")!, title: "B")

        let merged = HistorySuggestionMatcher.merge(siteMatches: [siteEntry], visitMatches: [visitEntry])

        XCTAssertEqual(merged.count, 2)
    }

    // MARK: - matches

    func testMatchesByURLDomainOrSiteDomain() {
        let entry = makeEntry(
            id: "1",
            url: URL(string: "https://www.youtube.com/watch?v=abc")!,
            title: "A video",
            domain: "www.youtube.com",
            siteDomain: "youtube.com"
        )

        XCTAssertTrue(HistorySuggestionMatcher.matches(entry, query: SearchTextQuery("youtube")))
        XCTAssertTrue(HistorySuggestionMatcher.matches(entry, query: SearchTextQuery("watch?v=abc")))
        XCTAssertFalse(HistorySuggestionMatcher.matches(entry, query: SearchTextQuery("completely-unrelated")))
    }

    // MARK: - appendURLMatchedSuggestions

    func testAppendURLMatchedSuggestionsRanksSpecificPageAheadOfBareRoot() {
        // A visited deep page is a more specific/deliberate match than the bare
        // site root, so it's ranked first (this mirrors the pre-existing,
        // preserved ordering — see the `lhsRoot`/`rhsRoot` comparison).
        let root = makeEntry(id: "root", url: URL(string: "https://example.com/")!, title: "Example Home")
        let deep = makeEntry(id: "deep", url: URL(string: "https://example.com/deep/page")!, title: "Deep Page")

        var suggestions: [SearchManager.SearchSuggestion] = []
        var seenKeys = Set<String>()

        HistorySuggestionMatcher.appendURLMatchedSuggestions(
            from: [root, deep],
            query: "example",
            maxVisibleSuggestions: 10,
            suggestions: &suggestions,
            seenKeys: &seenKeys
        )

        XCTAssertEqual(suggestions.count, 2)
        XCTAssertEqual(suggestions.first?.text, "Deep Page")
    }

    func testAppendURLMatchedSuggestionsSkipsAlreadySeenKeys() {
        let entry = makeEntry(id: "1", url: URL(string: "https://example.com/")!, title: "Example Home")
        let existing = SearchManager.SearchSuggestion(text: "Example Home", type: .history(entry))

        var suggestions: [SearchManager.SearchSuggestion] = [existing]
        var seenKeys: Set<String> = [SuggestionDeduplicationPolicy.deduplicationKey(for: existing)]

        HistorySuggestionMatcher.appendURLMatchedSuggestions(
            from: [entry],
            query: "example",
            maxVisibleSuggestions: 10,
            suggestions: &suggestions,
            seenKeys: &seenKeys
        )

        XCTAssertEqual(suggestions.count, 1)
    }

    func testAppendURLMatchedSuggestionsReplacesRemoteResultWhenAtCapacity() {
        let remote = SearchManager.SearchSuggestion(text: "remote phrase", type: .search)
        let historyEntry = makeEntry(id: "1", url: URL(string: "https://example.com/")!, title: "Example Home")

        var suggestions: [SearchManager.SearchSuggestion] = [remote]
        var seenKeys: Set<String> = [SuggestionDeduplicationPolicy.deduplicationKey(for: remote)]

        HistorySuggestionMatcher.appendURLMatchedSuggestions(
            from: [historyEntry],
            query: "example",
            maxVisibleSuggestions: 1,
            suggestions: &suggestions,
            seenKeys: &seenKeys
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.text, "Example Home")
    }

    func testAppendURLMatchedSuggestionsDoesNotReplaceOtherLocalNavigationResultsWhenAtCapacity() {
        let bookmark = SumiBookmark(id: "bm", title: "Bookmarked", url: URL(string: "https://kept.example")!, folderID: nil)
        let kept = SearchManager.SearchSuggestion(text: "Bookmarked", type: .bookmark(bookmark))
        let historyEntry = makeEntry(id: "1", url: URL(string: "https://example.com/")!, title: "Example Home")

        var suggestions: [SearchManager.SearchSuggestion] = [kept]
        var seenKeys: Set<String> = [SuggestionDeduplicationPolicy.deduplicationKey(for: kept)]

        HistorySuggestionMatcher.appendURLMatchedSuggestions(
            from: [historyEntry],
            query: "example",
            maxVisibleSuggestions: 1,
            suggestions: &suggestions,
            seenKeys: &seenKeys
        )

        XCTAssertEqual(suggestions.count, 1)
        XCTAssertEqual(suggestions.first?.text, "Bookmarked")
    }

    func testAppendURLMatchedSuggestionsDoesNothingForEmptyQuery() {
        let entry = makeEntry(id: "1", url: URL(string: "https://example.com/")!, title: "Example Home")
        var suggestions: [SearchManager.SearchSuggestion] = []
        var seenKeys = Set<String>()

        HistorySuggestionMatcher.appendURLMatchedSuggestions(
            from: [entry],
            query: "   ",
            maxVisibleSuggestions: 10,
            suggestions: &suggestions,
            seenKeys: &seenKeys
        )

        XCTAssertTrue(suggestions.isEmpty)
    }

    // MARK: - Helpers

    private func makeEntry(
        id: String,
        url: URL,
        title: String,
        domain: String = "example.com",
        siteDomain: String? = "example.com",
        isSiteAggregate: Bool = false,
        visitedAt: Date = Date()
    ) -> HistoryListItem {
        HistoryListItem(
            id: id,
            visitID: nil,
            url: url,
            title: title,
            domain: domain,
            siteDomain: siteDomain,
            visitedAt: visitedAt,
            timeText: "",
            visitCount: 1,
            isSiteAggregate: isSiteAggregate
        )
    }
}
