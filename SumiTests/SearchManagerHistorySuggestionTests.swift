import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SearchManagerHistorySuggestionTests: XCTestCase {
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
            $0.filter(\.isHistorySuggestion).count == 2
        }

        XCTAssertLessThanOrEqual(suggestions.count, 5)
        XCTAssertEqual(suggestions.filter(\.isHistorySuggestion).count, 2)
        XCTAssertEqual(suggestions.prefix(2).filter(\.isHistorySuggestion).count, 2)
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
            $0.filter(\.isHistorySuggestion).count == 2
        }

        XCTAssertLessThanOrEqual(suggestions.count, 5)
        XCTAssertEqual(suggestions.filter(\.isHistorySuggestion).count, 2)
        XCTAssertTrue(suggestions.allSatisfy { suggestion in
            !suggestion.isHistorySuggestion || suggestion.text.contains("Rapid")
        })
        harness.searchManager.clearSuggestions()
    }

    private func makeHarness() throws -> (
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
        let searchManager = SearchManager()
        searchManager.setHistoryManager(historyManager)
        return (container, historyManager, searchManager, profileID)
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

private extension SearchManager.SearchSuggestion {
    var isHistorySuggestion: Bool {
        if case .history = type {
            return true
        }
        return false
    }
}
