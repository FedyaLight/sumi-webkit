@testable import Sumi
import SumiDomain
import XCTest

final class SearchManagerURLNormalizationTests: XCTestCase {
    private let template = SearchProvider.google.queryTemplate

    func testNormalizeURLPassesThroughWebKitExtensionScheme() {
        let url =
            "webkit-extension://ext-31353238616531302d306536392d343862642d623263362d356234313731653934303063/help/index.html"
        XCTAssertEqual(normalizeURL(url, queryTemplate: template), url)
    }

    func testNormalizeURLPassesThroughWebKitExtensionSchemeCaseInsensitive() {
        let url = "WebKit-Extension://host/page.html"
        XCTAssertEqual(normalizeURL(url, queryTemplate: template), url)
    }

    func testNormalizeURLPassesThroughSafariWebExtensionScheme() {
        let url = "safari-web-extension://abcdef0123456789/options.html"
        XCTAssertEqual(normalizeURL(url, queryTemplate: template), url)
    }

    // Search text reaches the engine as a single intact `q` value. Before this,
    // `.urlQueryAllowed` left `&`/`=`/`+` unescaped, so anything after an `&`
    // became a separate query parameter and a typed `+` read as a space.
    func testNormalizeURLEncodesSpacesAsPlusForQueryPositionTemplates() {
        XCTAssertEqual(
            normalizeURL("voice over translation", queryTemplate: template),
            "https://www.google.com/search?q=voice+over+translation"
        )
    }

    func testNormalizeURLEscapesQueryDelimitersInSearchText() {
        XCTAssertEqual(
            normalizeURL("rust & c++", queryTemplate: template),
            "https://www.google.com/search?q=rust+%26+c%2B%2B"
        )
        XCTAssertEqual(
            normalizeURL("a=b", queryTemplate: template),
            "https://www.google.com/search?q=a%3Db"
        )
        XCTAssertEqual(
            normalizeURL("1+1", queryTemplate: template),
            "https://www.google.com/search?q=1%2B1"
        )
    }

    func testNormalizeURLKeepsPercentEncodedSpacesForPathPositionTemplates() {
        // `+` only means "space" in a query string, so a path token must not
        // get one. Spotify's default tab-to-search template is this shape.
        XCTAssertEqual(
            normalizeURL("daft punk", queryTemplate: "https://open.spotify.com/search/%@"),
            "https://open.spotify.com/search/daft%20punk"
        )
    }

    func testNormalizeURLLeavesUnrelatedPercentSequencesInTemplateIntact() {
        // Regression: `String(format:)` used to consume these.
        XCTAssertEqual(
            normalizeURL("sumi browser", queryTemplate: "https://example.com/s?q=%@&pct=100%25"),
            "https://example.com/s?q=sumi+browser&pct=100%25"
        )
    }
}
