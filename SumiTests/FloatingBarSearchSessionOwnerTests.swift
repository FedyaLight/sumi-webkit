import XCTest

@testable import Sumi

@MainActor
final class FloatingBarSearchSessionOwnerTests: XCTestCase {
    func testNavigateSuggestionsPreviewsAndRestoresOriginalText() {
        let owner = FloatingBarSearchSessionOwner()
        owner.text = "original query"
        owner.searchManager.suggestions = [
            SearchManager.SearchSuggestion(
                text: "https://example.com",
                type: .url
            )
        ]

        owner.navigateSuggestions(direction: 1)

        XCTAssertEqual(owner.selectedSuggestionIndex, 0)
        XCTAssertEqual(owner.text, "https://example.com")
        XCTAssertTrue(owner.isSuggestionPreviewActive)

        owner.navigateSuggestions(direction: -1)

        XCTAssertEqual(owner.selectedSuggestionIndex, -1)
        XCTAssertEqual(owner.text, "original query")
        XCTAssertFalse(owner.isSuggestionPreviewActive)
    }

    func testNavigateSuggestionsClampsToBounds() {
        let owner = FloatingBarSearchSessionOwner()
        owner.searchManager.suggestions = [
            SearchManager.SearchSuggestion(text: "first", type: .search),
            SearchManager.SearchSuggestion(text: "second", type: .search)
        ]

        owner.navigateSuggestions(direction: 1)
        owner.navigateSuggestions(direction: 1)
        owner.navigateSuggestions(direction: 1)

        XCTAssertEqual(owner.selectedSuggestionIndex, 1)
        XCTAssertEqual(owner.text, "second")

        owner.navigateSuggestions(direction: -1)
        owner.navigateSuggestions(direction: -1)
        owner.navigateSuggestions(direction: -1)

        XCTAssertEqual(owner.selectedSuggestionIndex, -1)
        XCTAssertFalse(owner.isSuggestionPreviewActive)
    }

    func testVisibleSuggestionsFiltersToSearchSuggestionsDuringSiteSearch() {
        let owner = FloatingBarSearchSessionOwner()
        owner.activeSiteSearch = SumiSearchEngine(
            name: "Example",
            domain: "example.com",
            searchURLTemplate: "https://example.com/search?q={query}",
            colorHex: "#0000ff",
            tabSearchEnabled: true
        )
        owner.searchManager.suggestions = [
            SearchManager.SearchSuggestion(text: "query", type: .search),
            SearchManager.SearchSuggestion(text: "https://example.com", type: .url)
        ]

        XCTAssertEqual(owner.visibleSuggestions.map(\.text), ["query"])
    }
}
