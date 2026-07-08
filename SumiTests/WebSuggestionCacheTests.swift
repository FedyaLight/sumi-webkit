//
//  WebSuggestionCacheTests.swift
//  SumiTests
//
//

import XCTest

@testable import Sumi

final class WebSuggestionCacheTests: XCTestCase {
    func testStoredSuggestionsAreRetrievableByQuery() {
        var cache = WebSuggestionCache(capacity: 3)
        let suggestions = [SumiSuggestionEngine.APISuggestion(phrase: "swift", isNav: false)]

        cache.store(suggestions, for: "swi")

        XCTAssertEqual(cache.suggestions(for: "swi")?.first?.phrase, "swift")
    }

    func testUnknownQueryReturnsNil() {
        let cache = WebSuggestionCache(capacity: 3)
        XCTAssertNil(cache.suggestions(for: "missing"))
    }

    func testStoringSameQueryTwiceOverwritesAndRefreshesRecency() {
        var cache = WebSuggestionCache(capacity: 2)
        cache.store([SumiSuggestionEngine.APISuggestion(phrase: "a-phrase", isNav: false)], for: "a")
        cache.store([SumiSuggestionEngine.APISuggestion(phrase: "b-phrase", isNav: false)], for: "b")
        // Re-storing "a" refreshes its recency, so "b" becomes the least-recently-used entry.
        cache.store([SumiSuggestionEngine.APISuggestion(phrase: "second", isNav: false)], for: "a")

        // Capacity is 2, so adding a third query must evict "b", not the refreshed "a".
        cache.store([SumiSuggestionEngine.APISuggestion(phrase: "c-phrase", isNav: false)], for: "c")

        XCTAssertEqual(cache.suggestions(for: "a")?.first?.phrase, "second")
        XCTAssertNil(cache.suggestions(for: "b"))
        XCTAssertEqual(cache.suggestions(for: "c")?.first?.phrase, "c-phrase")
    }

    func testCapacityEvictsLeastRecentlyStoredQuery() {
        var cache = WebSuggestionCache(capacity: 2)
        cache.store([SumiSuggestionEngine.APISuggestion(phrase: "one", isNav: false)], for: "1")
        cache.store([SumiSuggestionEngine.APISuggestion(phrase: "two", isNav: false)], for: "2")
        cache.store([SumiSuggestionEngine.APISuggestion(phrase: "three", isNav: false)], for: "3")

        XCTAssertNil(cache.suggestions(for: "1"))
        XCTAssertNotNil(cache.suggestions(for: "2"))
        XCTAssertNotNil(cache.suggestions(for: "3"))
    }
}
