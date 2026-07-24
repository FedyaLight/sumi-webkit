//
//  SuggestionDeduplicationPolicyTests.swift
//  SumiTests
//
//

import XCTest

@testable import Sumi

@MainActor
final class SuggestionDeduplicationPolicyTests: XCTestCase {
    // MARK: - canonicalNavigationKey

    func testCanonicalNavigationKeyIgnoresSchemeAndTrailingRootSlash() {
        let withSlash = URL(string: "https://example.com/")!
        let withoutSlash = URL(string: "http://example.com")!

        XCTAssertEqual(
            SuggestionDeduplicationPolicy.canonicalNavigationKey(for: withSlash),
            SuggestionDeduplicationPolicy.canonicalNavigationKey(for: withoutSlash)
        )
    }

    func testCanonicalNavigationKeyIgnoresFragmentUserAndPassword() {
        let bare = URL(string: "https://example.com/path")!
        let decorated = URL(string: "https://user:pass@example.com/path#section")!

        XCTAssertEqual(
            SuggestionDeduplicationPolicy.canonicalNavigationKey(for: bare),
            SuggestionDeduplicationPolicy.canonicalNavigationKey(for: decorated)
        )
    }

    func testCanonicalNavigationKeyDistinguishesDifferentPaths() {
        let a = URL(string: "https://example.com/a")!
        let b = URL(string: "https://example.com/b")!

        XCTAssertNotEqual(
            SuggestionDeduplicationPolicy.canonicalNavigationKey(for: a),
            SuggestionDeduplicationPolicy.canonicalNavigationKey(for: b)
        )
    }

    // MARK: - deduplicationKey

    func testDeduplicationKeyTreatsSearchTextCaseAndWhitespaceInsensitively() {
        let lhs = SearchManager.SearchSuggestion(text: "  Swift Concurrency ", type: .search)
        let rhs = SearchManager.SearchSuggestion(text: "swift concurrency", type: .search)

        XCTAssertEqual(
            SuggestionDeduplicationPolicy.deduplicationKey(for: lhs),
            SuggestionDeduplicationPolicy.deduplicationKey(for: rhs)
        )
    }

    func testDeduplicationKeyMatchesEquivalentURLsAcrossSuggestionKinds() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        let bookmark = SumiBookmark(id: "bm-1", title: "Reference", url: url, folderID: nil)

        let urlSuggestion = SearchManager.SearchSuggestion(text: url.absoluteString, type: .url)
        let bookmarkSuggestion = SearchManager.SearchSuggestion(text: "Reference", type: .bookmark(bookmark))

        XCTAssertEqual(
            SuggestionDeduplicationPolicy.deduplicationKey(for: urlSuggestion),
            SuggestionDeduplicationPolicy.deduplicationKey(for: bookmarkSuggestion)
        )
    }

    func testDeduplicationKeyDistinguishesSearchFromURLWithSameText() {
        let search = SearchManager.SearchSuggestion(text: "example.com", type: .search)
        let url = SearchManager.SearchSuggestion(text: "example.com", type: .url)

        XCTAssertNotEqual(
            SuggestionDeduplicationPolicy.deduplicationKey(for: search),
            SuggestionDeduplicationPolicy.deduplicationKey(for: url)
        )
    }

    // MARK: - isLocalNavigationSuggestion

    func testIsLocalNavigationSuggestionIsTrueForHistoryBookmarkAndTab() throws {
        let url = try XCTUnwrap(URL(string: "https://example.com"))
        let bookmark = SumiBookmark(id: "bm-1", title: "Example", url: url, folderID: nil)
        let historyEntry = HistoryListItem(
            id: "h1",
            visitID: nil,
            url: url,
            title: "Example",
            domain: "example.com",
            siteDomain: "example.com",
            visitedAt: Date(),
            timeText: "",
            visitCount: 1,
            isSiteAggregate: false
        )

        XCTAssertTrue(SuggestionDeduplicationPolicy.isLocalNavigationSuggestion(
            .init(text: "Example", type: .bookmark(bookmark))
        ))
        XCTAssertTrue(SuggestionDeduplicationPolicy.isLocalNavigationSuggestion(
            .init(text: "Example", type: .history(historyEntry))
        ))
    }

    func testIsLocalNavigationSuggestionIsFalseForSearchAndURL() {
        XCTAssertFalse(SuggestionDeduplicationPolicy.isLocalNavigationSuggestion(
            .init(text: "weather", type: .search)
        ))
        XCTAssertFalse(SuggestionDeduplicationPolicy.isLocalNavigationSuggestion(
            .init(text: "https://example.com", type: .url)
        ))
    }

    // MARK: - directURLSuggestion

    func testDirectURLSuggestionNormalizesBareDomain() {
        let suggestion = SuggestionDeduplicationPolicy.directURLSuggestion(for: "example.com")

        XCTAssertNotNil(suggestion)
        if case .url = suggestion?.type {
            XCTAssertTrue(suggestion?.text.contains("example.com") ?? false)
        } else {
            XCTFail("Expected a .url suggestion")
        }
    }

    func testDirectURLSuggestionIsNilForPlainSearchPhrase() {
        XCTAssertNil(SuggestionDeduplicationPolicy.directURLSuggestion(for: "how to bake bread"))
    }
}
