import XCTest

@testable import Sumi

final class AdblockCosmeticDomainIndexTests: XCTestCase {
    func testParsesSelectorDomainEntries() throws {
        let json: [[String: Any]] = [
            ["s": ".banner", "d": ["*example.com"]],
            ["s": "#promo", "d": ["specific.org", "*other.org"]],
        ]
        let index = try AdblockCosmeticDomainIndex(
            json: json
        )
        XCTAssertEqual(index.selectors(forHost: "www.example.com"), [".banner"])
        XCTAssertEqual(index.selectors(forHost: "example.com"), [".banner"])
        XCTAssertEqual(index.selectors(forHost: "badexample.com"), [".banner"])
        XCTAssertEqual(index.selectors(forHost: "specific.org"), ["#promo"])
        XCTAssertEqual(index.selectors(forHost: "a.other.org"), ["#promo"])
        XCTAssertEqual(index.selectors(forHost: "other.org.evil.io"), [])
    }

    func testCaseInsensitiveHostMatching() throws {
        let index = try AdblockCosmeticDomainIndex(
            json: [["s": ".ad", "d": ["*Example.COM"]]]
        )
        XCTAssertEqual(index.selectors(forHost: "WWW.EXAMPLE.com"), [".ad"])
    }

    func testPatternWithoutWildcardRequiresExactHost() throws {
        let index = try AdblockCosmeticDomainIndex(
            json: [["s": ".x", "d": ["exact.org"]]]
        )
        XCTAssertEqual(index.selectors(forHost: "exact.org"), [".x"])
        XCTAssertEqual(index.selectors(forHost: "sub.exact.org"), [])
    }

    func testEmptyAndMissingHostsReturnNothing() throws {
        let index = try AdblockCosmeticDomainIndex(
            json: [["s": ".ad", "d": ["*example.com"]]]
        )
        XCTAssertTrue(index.selectors(forHost: nil).isEmpty)
        XCTAssertTrue(index.selectors(forHost: "").isEmpty)
        XCTAssertTrue(AdblockCosmeticDomainIndex().selectors(forHost: "example.com").isEmpty)
    }

    func testInvalidPayloadThrows() {
        XCTAssertThrowsError(try AdblockCosmeticDomainIndex(json: "nope"))
        XCTAssertThrowsError(
            try AdblockCosmeticDomainIndex(json: [["s": "", "d": ["*a.com"]]])
        )
        XCTAssertThrowsError(
            try AdblockCosmeticDomainIndex(json: [["s": ".a", "d": []]])
        )
    }
}
