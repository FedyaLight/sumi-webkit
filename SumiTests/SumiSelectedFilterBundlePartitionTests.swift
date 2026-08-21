import XCTest

@testable import Sumi

final class SumiSelectedFilterBundleBuilderPartitionTests: XCTestCase {
    private let blockRule: [String: Any] = [
        "action": ["type": "block"],
        "trigger": ["url-filter": "||ads.example^"],
    ]
    private let genericCosmeticRule: [String: Any] = [
        "action": ["type": "css-display-none", "selector": ".generic-ad"],
        "trigger": ["url-filter": ".*"],
    ]
    private let domainCosmeticRule: [String: Any] = [
        "action": ["type": "css-display-none", "selector": ".domain-ad"],
        "trigger": ["url-filter": ".*", "if-domain": ["*news.example"]],
    ]
    private let unlessDomainCosmeticRule: [String: Any] = [
        "action": ["type": "css-display-none", "selector": ".unless-ad"],
        "trigger": ["url-filter": ".*", "unless-domain": ["keep.example"]],
    ]

    func testExtractsOnlyIfDomainCosmetics() throws {
        let conversion = SumiSelectedFilterBundleBuilder.Conversion(
            json: try JSONSerialization.data(withJSONObject: [
                blockRule,
                genericCosmeticRule,
                domainCosmeticRule,
                unlessDomainCosmeticRule,
            ]),
            safariRuleCount: 4,
            advancedRules: "",
            discardedRuleCount: 0
        )

        let (partitioned, cosmetics) = try SumiSelectedFilterBundleBuilder
            .partitionDomainCosmetics(conversion)

        XCTAssertEqual(cosmetics.map(\.selector), [".domain-ad"])
        XCTAssertEqual(cosmetics.first?.domains, ["*news.example"])

        let kept = try JSONSerialization.jsonObject(with: partitioned.json)
            as? [[String: Any]]
        XCTAssertEqual(kept?.count, 3)
        let selectors: [String?] = (kept ?? []).map {
            ($0["action"] as? [String: Any])?["selector"] as? String
        }
        XCTAssertEqual(selectors.count, 3)
        XCTAssertNil(selectors[0])
        XCTAssertEqual(selectors[1], ".generic-ad")
        XCTAssertEqual(selectors[2], ".unless-ad")
        XCTAssertEqual(partitioned.safariRuleCount, 3)
    }

    func testConversionWithoutIfDomainCosmeticsIsUnchanged() throws {
        let original = SumiSelectedFilterBundleBuilder.Conversion(
            json: try JSONSerialization.data(withJSONObject: [blockRule]),
            safariRuleCount: 1,
            advancedRules: "",
            discardedRuleCount: 0
        )
        let (partitioned, cosmetics) = try SumiSelectedFilterBundleBuilder
            .partitionDomainCosmetics(original)
        XCTAssertTrue(cosmetics.isEmpty)
        XCTAssertEqual(partitioned.json, original.json)
        XCTAssertEqual(partitioned.safariRuleCount, 1)
    }
}
