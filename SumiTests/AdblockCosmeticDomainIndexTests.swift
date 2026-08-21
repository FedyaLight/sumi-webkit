import XCTest

@testable import Sumi

final class AdblockCosmeticDomainIndexTests: XCTestCase {
    func testParsesSelectorDomainEntries() throws {
        let entries = [
            AdblockCosmeticDomainIndex.Entry(
                selector: ".banner",
                domains: ["*example.com"]
            ),
            AdblockCosmeticDomainIndex.Entry(
                selector: "#promo",
                domains: ["specific.org", "*other.org"]
            ),
        ]
        let index = try AdblockCosmeticDomainIndex(entries: entries)
        XCTAssertEqual(index.selectors(forHost: "www.example.com"), [".banner"])
        XCTAssertEqual(index.selectors(forHost: "example.com"), [".banner"])
        XCTAssertEqual(index.selectors(forHost: "badexample.com"), [])
        XCTAssertEqual(index.selectors(forHost: "specific.org"), ["#promo"])
        XCTAssertEqual(index.selectors(forHost: "a.other.org"), ["#promo"])
        XCTAssertEqual(index.selectors(forHost: "other.org.evil.io"), [])
    }

    func testCaseInsensitiveHostMatching() throws {
        let index = try AdblockCosmeticDomainIndex(
            entries: [.init(selector: ".ad", domains: ["*Example.COM"])]
        )
        XCTAssertEqual(index.selectors(forHost: "WWW.EXAMPLE.com"), [".ad"])
    }

    func testPatternWithoutWildcardRequiresExactHost() throws {
        let index = try AdblockCosmeticDomainIndex(
            entries: [.init(selector: ".x", domains: ["exact.org"])]
        )
        XCTAssertEqual(index.selectors(forHost: "exact.org"), [".x"])
        XCTAssertEqual(index.selectors(forHost: "sub.exact.org"), [])
    }

    func testEmptyAndMissingHostsReturnNothing() throws {
        let index = try AdblockCosmeticDomainIndex(
            entries: [.init(selector: ".ad", domains: ["*example.com"])]
        )
        XCTAssertTrue(index.selectors(forHost: nil).isEmpty)
        XCTAssertTrue(index.selectors(forHost: "").isEmpty)
        XCTAssertTrue(AdblockCosmeticDomainIndex().selectors(forHost: "example.com").isEmpty)
    }

    func testInvalidPayloadThrows() {
        XCTAssertThrowsError(
            try AdblockCosmeticDomainIndex(
                entries: [.init(selector: "", domains: ["*a.com"])]
            )
        )
        XCTAssertThrowsError(
            try AdblockCosmeticDomainIndex(
                entries: [.init(selector: ".a", domains: [])]
            )
        )
        XCTAssertThrowsError(try AdblockCosmeticDomainIndex(data: Data("{}".utf8)))
    }

    func testPreservesRuleOrderAndDeduplicatesMultiPatternMatches() throws {
        let index = try AdblockCosmeticDomainIndex(entries: [
            .init(
                selector: ".first",
                domains: ["*example.com", "www.example.com"]
            ),
            .init(selector: ".second", domains: ["*example.com"]),
        ])

        XCTAssertEqual(
            index.selectors(forHost: "www.example.com"),
            [".first", ".second"]
        )
    }

    func testSplitRulesExtractsOnlyPortableCosmetics() throws {
        let rules: [[String: Any]] = [
            [
                "action": ["type": "block"],
                "trigger": ["url-filter": "||ads.example^"],
            ],
            [
                "action": ["type": "css-display-none", "selector": ".generic"],
                "trigger": ["url-filter": ".*"],
            ],
            [
                "action": ["type": "css-display-none", "selector": ".domain"],
                "trigger": ["url-filter": ".*", "if-domain": ["*news.example"]],
            ],
            [
                "action": ["type": "css-display-none", "selector": ".unless"],
                "trigger": ["url-filter": ".*", "unless-domain": ["keep.example"]],
            ],
        ]
        let split = AdblockCosmeticDomainIndex.splitRules(rules)
        XCTAssertEqual(split.network.count, 3)
        XCTAssertEqual(split.cosmetics.count, 1)
        XCTAssertEqual(split.cosmetics.first?.selector, ".domain")
        XCTAssertEqual(split.cosmetics.first?.domains, ["*news.example"])

        // The extracted payload must round-trip through the index.
        let index = try AdblockCosmeticDomainIndex(
            entries: split.cosmetics
        )
        XCTAssertEqual(index.selectors(forHost: "www.news.example"), [".domain"])
    }
}
