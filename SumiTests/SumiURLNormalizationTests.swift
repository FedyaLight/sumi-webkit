import XCTest

@testable import Sumi

final class SumiURLNormalizationTests: XCTestCase {
    func testSearchBarPreservesExplicitScheme() {
        let normalized = SumiURLNormalization.normalize(
            "https://example.com/path",
            context: .searchBar(queryTemplate: "https://duck.test/?q=%@")
        )
        XCTAssertEqual(normalized, "https://example.com/path")
    }

    func testSearchBarBareDomainGetsHTTPS() {
        // Dotted input that URLPredictor treats as search falls back to https:// prefix.
        let normalized = SumiURLNormalization.normalize(
            "16385-12228.72",
            context: .searchBar(queryTemplate: "https://duck.test/?q=%@")
        )
        XCTAssertEqual(normalized, "https://16385-12228.72")
    }

    func testSearchBarClassifierNavigatePreservesURL() {
        let normalized = SumiURLNormalization.normalize(
            "regular-domain.com",
            context: .searchBar(queryTemplate: "https://duck.test/?q=%@")
        )
        XCTAssertEqual(normalized, "http://regular-domain.com/")
    }

    func testSearchBarQueryUsesTemplate() {
        let normalized = SumiURLNormalization.normalize(
            "privacy+search",
            context: .searchBar(queryTemplate: "https://duck.test/?q=%@")
        )
        XCTAssertEqual(normalized, "https://duck.test/?q=privacy+search")
    }

    func testStartupPageAllowsBareDomain() {
        XCTAssertEqual(
            SumiURLNormalization.normalizedStartupURLString(from: "example.com"),
            "https://example.com"
        )
        XCTAssertNil(SumiURLNormalization.normalizedStartupURLString(from: "plain search text"))
    }

    func testNewTabPageAllowsBareDomain() {
        XCTAssertEqual(
            SumiURLNormalization.normalizedNewTabURLString(from: "example.com"),
            "https://example.com"
        )
        XCTAssertNil(SumiURLNormalization.normalizedNewTabURLString(from: "plain search text"))
    }

    func testShortcutEditorNormalizesBareDomain() {
        XCTAssertEqual(
            SumiURLNormalization.normalizedShortcutURLString(from: "example.com"),
            "https://example.com"
        )
        XCTAssertNil(SumiURLNormalization.normalizedShortcutURLString(from: " "))
    }

    func testSearchEngineTemplateAddsHTTPS() {
        XCTAssertEqual(
            SumiURLNormalization.normalizedSearchEngineTemplate("search.example/q=%@"),
            "https://search.example/q=%@"
        )
    }
}
