import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SearchManagerHistorySuggestionTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testHistorySuggestionsAreBoundedAndRankedBeforeWebSuggestions() async throws {
        let harness = try makeHarness()
        for index in 0..<8 {
            try await recordVisit(
                url: URL(string: "https://bounded.example/\(index)")!,
                title: "Bounded Match \(index)",
                at: Date().addingTimeInterval(TimeInterval(index)),
                harness: harness
            )
        }

        harness.searchManager.searchSuggestions(for: "bounded")
        let suggestions = await waitForSuggestions(in: harness.searchManager) {
            $0.filter(\.isHistorySuggestion).count >= 5
        }

        XCTAssertLessThanOrEqual(suggestions.count, 10)
        XCTAssertGreaterThanOrEqual(suggestions.filter(\.isHistorySuggestion).count, 5)
        XCTAssertTrue(suggestions.prefix(5).allSatisfy(\.isHistorySuggestion))
        harness.searchManager.clearSuggestions()
    }

    func testNewerHistoryQuerySupersedesOlderQuery() async throws {
        let harness = try makeHarness()
        try await recordVisit(
            url: URL(string: "https://alpha.example")!,
            title: "Alpha Result",
            at: Date().addingTimeInterval(-10),
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://beta.example")!,
            title: "Beta Result",
            at: Date(),
            harness: harness
        )

        harness.searchManager.searchSuggestions(for: "alpha")
        harness.searchManager.searchSuggestions(for: "beta")

        let suggestions = await waitForSuggestions(in: harness.searchManager) {
            $0.contains { $0.text == "Beta Result" }
        }

        XCTAssertTrue(suggestions.contains { $0.text == "Beta Result" })
        XCTAssertFalse(suggestions.contains { $0.text == "Alpha Result" })
        XCTAssertLessThanOrEqual(suggestions.count, 5)
        harness.searchManager.clearSuggestions()
    }

    func testRapidTypingKeepsOnlyCurrentBoundedHistoryResults() async throws {
        let harness = try makeHarness()
        for index in 0..<5 {
            try await recordVisit(
                url: URL(string: "https://rapid.example/\(index)")!,
                title: "Rapid Result \(index)",
                at: Date().addingTimeInterval(TimeInterval(index)),
                harness: harness
            )
        }

        harness.searchManager.searchSuggestions(for: "r")
        harness.searchManager.searchSuggestions(for: "ra")
        harness.searchManager.searchSuggestions(for: "rapid")

        let suggestions = await waitForSuggestions(in: harness.searchManager) {
            $0.filter(\.isHistorySuggestion).count >= 5
        }

        XCTAssertLessThanOrEqual(suggestions.count, 10)
        XCTAssertGreaterThanOrEqual(suggestions.filter(\.isHistorySuggestion).count, 5)
        XCTAssertTrue(suggestions.allSatisfy { suggestion in
            !suggestion.isHistorySuggestion || suggestion.text.contains("Rapid")
        })
        harness.searchManager.clearSuggestions()
    }

    func testHistorySuggestionsMatchDiacriticInsensitiveText() async throws {
        let harness = try makeHarness()
        try await recordVisit(
            url: URL(string: "https://coffee.example")!,
            title: "Café Central",
            at: Date(),
            harness: harness
        )

        harness.searchManager.searchSuggestions(for: "cafe")
        let suggestions = await waitForSuggestions(in: harness.searchManager) {
            $0.contains { $0.text == "Café Central" }
        }

        XCTAssertTrue(suggestions.contains { $0.text == "Café Central" })
        harness.searchManager.clearSuggestions()
    }

    func testWebSuggestionsDecodeNumericHTMLEntities() async {
        let payload = """
        [{"phrase":"&#1087;&#1086;&#1075;&#1086;&#1076;&#1072; &#1084;&#1086;&#1089;&#1082;&#1074;&#1072;","is_nav":false}]
        """
        let searchManager = SearchManager(
            suggestionDataProvider: StaticSearchSuggestionDataProvider(payload: payload)
        )

        searchManager.searchSuggestions(for: "погода")
        let suggestions = await waitForSuggestions(in: searchManager) {
            $0.contains { $0.text == "погода москва" }
        }

        XCTAssertTrue(suggestions.contains { $0.text == "погода москва" })
        XCTAssertFalse(suggestions.contains { $0.text.contains("&#") })
        searchManager.clearSuggestions()
    }

    func testDuckDuckGoNavigationalSuggestionMapsSnakeCaseIsNavToURL() async {
        let payload = """
        [{"phrase":"swift.org","is_nav":true}]
        """
        let searchManager = SearchManager(
            suggestionDataProvider: StaticSearchSuggestionDataProvider(payload: payload)
        )

        searchManager.searchSuggestions(for: "swift")
        let suggestions = await waitForSuggestions(in: searchManager) {
            $0.contains { $0.text == "http://swift.org" && $0.isURLSuggestion }
        }

        XCTAssertTrue(suggestions.contains { $0.text == "http://swift.org" && $0.isURLSuggestion })
        searchManager.clearSuggestions()
    }

    func testDirectURLInputStillProducesOpenURLSuggestion() async {
        let searchManager = SearchManager(
            suggestionDataProvider: StaticSearchSuggestionDataProvider(payload: "[]")
        )

        searchManager.searchSuggestions(for: "example.com")
        let suggestions = await waitForSuggestions(in: searchManager) {
            $0.contains { $0.isNormalizedExampleURLSuggestion }
        }

        XCTAssertTrue(suggestions.contains { $0.isNormalizedExampleURLSuggestion })
        searchManager.clearSuggestions()
    }

    func testBookmarkSuggestionsAreIncludedInLocalResults() async throws {
        let bookmarkManager = makeBookmarkManager()
        let bookmark = try bookmarkManager.createBookmark(
            url: try XCTUnwrap(URL(string: "https://docs.example/reference")),
            title: "Reference Docs"
        )
        let searchManager = SearchManager(
            suggestionDataProvider: StaticSearchSuggestionDataProvider(payload: "[]")
        )
        searchManager.setBookmarkManager(bookmarkManager)

        searchManager.searchSuggestions(for: "docs")
        let suggestions = await waitForSuggestions(in: searchManager) {
            $0.contains { $0.text == bookmark.title && $0.isBookmarkSuggestion }
        }

        XCTAssertTrue(suggestions.contains { $0.text == bookmark.title && $0.isBookmarkSuggestion })
        searchManager.clearSuggestions()
    }

    func testVisitedSiteNameRanksBeforeRemoteSearchSuggestions() async throws {
        let harness = try makeHarness(
            suggestionPayload: """
            [{"phrase":"github copilot","is_nav":false},{"phrase":"github actions","is_nav":false}]
            """
        )
        let referenceDate = Date()
        for index in 0..<5 {
            try await recordVisit(
                url: URL(string: "https://github.com/sumi/\(index)")!,
                title: "GitHub",
                at: referenceDate.addingTimeInterval(TimeInterval(index)),
                harness: harness
            )
        }

        harness.searchManager.searchSuggestions(for: "github")
        let suggestions = await waitForSuggestions(in: harness.searchManager) {
            $0.contains { $0.text == "github copilot" }
                && $0.contains { $0.text == "GitHub" && $0.isHistorySuggestion }
        }

        XCTAssertEqual(suggestions.first?.text, "GitHub")
        XCTAssertTrue(suggestions.first?.isHistorySuggestion == true)
        harness.searchManager.clearSuggestions()
    }

    func testTopLinkSuggestionsIncludeBookmarksWithoutQuery() async throws {
        let bookmarkManager = makeBookmarkManager()
        let bookmark = try bookmarkManager.createBookmark(
            url: try XCTUnwrap(URL(string: "https://empty-state.example")),
            title: "Empty State Link"
        )
        let searchManager = SearchManager(
            suggestionDataProvider: StaticSearchSuggestionDataProvider(payload: "[]")
        )
        searchManager.setBookmarkManager(bookmarkManager)

        searchManager.showTopLinkSuggestions(limit: 5)
        let suggestions = await waitForSuggestions(in: searchManager) {
            $0.contains { $0.text == bookmark.title && $0.isBookmarkSuggestion }
        }

        XCTAssertTrue(suggestions.contains { $0.text == bookmark.title && $0.isBookmarkSuggestion })
        searchManager.clearSuggestions()
    }

    func testTopLinkSuggestionsPreferFrequentlyVisitedSites() async throws {
        let harness = try makeHarness()
        let referenceDate = Date()

        try await recordVisit(
            url: URL(string: "https://aaa-low.example")!,
            title: "Low Frequency",
            at: referenceDate,
            harness: harness
        )
        for index in 0..<5 {
            try await recordVisit(
                url: URL(string: "https://zzz-high.example/\(index)")!,
                title: "High Frequency",
                at: referenceDate.addingTimeInterval(TimeInterval(index + 1)),
                harness: harness
            )
        }

        harness.searchManager.showTopLinkSuggestions(limit: 2)
        let suggestions = await waitForSuggestions(in: harness.searchManager) {
            $0.contains { $0.text == "High Frequency" && $0.isHistorySuggestion }
        }

        XCTAssertEqual(suggestions.first?.text, "High Frequency")
        XCTAssertTrue(suggestions.first?.isHistorySuggestion == true)
        harness.searchManager.clearSuggestions()
    }

    private func makeHarness(
        suggestionPayload: String = "[]"
    ) throws -> (
        container: ModelContainer,
        historyManager: HistoryManager,
        searchManager: SearchManager,
        profileID: UUID
    ) {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let profileID = UUID()
        let historyManager = HistoryManager(context: context, profileId: profileID)
        let searchManager = SearchManager(
            suggestionDataProvider: StaticSearchSuggestionDataProvider(payload: suggestionPayload)
        )
        searchManager.setHistoryManager(historyManager)
        return (container, historyManager, searchManager, profileID)
    }

    private func makeBookmarkManager() -> SumiBookmarkManager {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SearchManagerBookmarkTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return SumiBookmarkManager(
            database: SumiBookmarkDatabase(directory: directory),
            syncFavicons: false
        )
    }

    private func recordVisit(
        url: URL,
        title: String,
        at timestamp: Date,
        harness: (
            container: ModelContainer,
            historyManager: HistoryManager,
            searchManager: SearchManager,
            profileID: UUID
        )
    ) async throws {
        _ = try await harness.historyManager.store.recordVisit(
            url: url,
            title: title,
            visitedAt: timestamp,
            profileId: harness.profileID
        )
    }

    private func waitForSuggestions(
        in searchManager: SearchManager,
        matching predicate: ([SearchManager.SearchSuggestion]) -> Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> [SearchManager.SearchSuggestion] {
        for _ in 0..<50 {
            let suggestions = searchManager.suggestions
            if predicate(suggestions) {
                return suggestions
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for search suggestions", file: file, line: line)
        return searchManager.suggestions
    }
}

@MainActor
private struct StaticSearchSuggestionDataProvider: SearchSuggestionDataProviding {
    let payload: String

    func data(for query: String) async throws -> Data {
        Data(payload.utf8)
    }
}

private extension SearchManager.SearchSuggestion {
    var isHistorySuggestion: Bool {
        if case .history = type {
            return true
        }
        return false
    }

    var isURLSuggestion: Bool {
        if case .url = type {
            return true
        }
        return false
    }

    var isBookmarkSuggestion: Bool {
        if case .bookmark = type {
            return true
        }
        return false
    }

    var isNormalizedExampleURLSuggestion: Bool {
        isURLSuggestion && text.contains("example.com")
    }
}
