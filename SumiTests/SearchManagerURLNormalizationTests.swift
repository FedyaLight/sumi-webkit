import XCTest
@testable import Sumi

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
}
