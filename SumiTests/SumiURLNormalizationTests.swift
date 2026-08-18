import XCTest

@testable import Sumi
import SumiDomain

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
        XCTAssertEqual(normalized, "https://regular-domain.com/")
    }

    func testSearchBarQueryUsesTemplate() {
        // A typed `+` is part of the search text, so it has to survive as
        // `%2B`. Passing it through literally made the engine read it as a
        // space, which is what `+` means in a query string.
        let normalized = SumiURLNormalization.normalize(
            "privacy+search",
            context: .searchBar(queryTemplate: "https://duck.test/?q=%@")
        )
        XCTAssertEqual(normalized, "https://duck.test/?q=privacy%2Bsearch")
    }

    func testSearchBarQueryEncodesTypedSpaceAsPlus() {
        let normalized = SumiURLNormalization.normalize(
            "privacy search",
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
