import SumiDomain
import XCTest

@testable import Sumi

final class ProtectionRuleAnalysisTests: XCTestCase {
    func testDeduplicationReportsEachRemovalReasonWithoutDroppingInvalidJSON() {
        let kept = planned(
            identifier: "keep",
            group: .trackingNetwork,
            source: .tracking,
            json: Self.exampleRuleJSON,
            contentHash: "tracking-hash"
        )
        let duplicateIdentifier = planned(
            identifier: "keep",
            group: .adblockAdsPrivacyNetwork,
            source: .adblock,
            json: Self.otherRuleJSON,
            contentHash: "identifier-hash"
        )
        let duplicateGroupHash = planned(
            identifier: "duplicate-group-hash",
            group: .trackingNetwork,
            source: .tracking,
            json: Self.otherRuleJSON,
            contentHash: "tracking-hash"
        )
        let duplicateCanonicalJSON = planned(
            identifier: "duplicate-canonical-json",
            group: .adblockAdsPrivacyNetwork,
            source: .adblock,
            json: Self.exampleRuleJSON,
            contentHash: "canonical-hash"
        )
        let invalidJSON = planned(
            identifier: "invalid-json",
            group: .adblockAdsPrivacyNetwork,
            source: .adblock,
            json: "{",
            contentHash: "invalid-hash"
        )

        let result = ProtectionRuleDeduplication.deduplicate([
            kept,
            duplicateIdentifier,
            duplicateGroupHash,
            duplicateCanonicalJSON,
            invalidJSON,
        ])

        XCTAssertEqual(
            result.definitions.map(\.definition.webKitStoreIdentifier),
            ["keep", "invalid-json"]
        )
        XCTAssertEqual(result.summary.inputRuleListCount, 5)
        XCTAssertEqual(result.summary.finalRuleListCount, 2)
        XCTAssertEqual(result.summary.duplicateIdentifierCountRemoved, 1)
        XCTAssertEqual(result.summary.duplicateGroupContentHashCountRemoved, 1)
        XCTAssertEqual(result.summary.duplicateCanonicalJSONCountRemoved, 1)
        XCTAssertEqual(result.summary.canonicalJSONUnavailableCount, 1)
        XCTAssertEqual(
            result.summary.removedIdentifiers,
            [
                "duplicate-canonical-json",
                "duplicate-group-hash",
                "keep",
            ]
        )
    }

    func testOverlapDiagnosticsCompareCanonicalRulesAndHostTokensAcrossSources() {
        let tracking = planned(
            identifier: "tracking",
            group: .trackingNetwork,
            source: .tracking,
            json: Self.exampleRuleJSON,
            contentHash: "tracking-hash"
        )
        let adblock = planned(
            identifier: "adblock",
            group: .adblockAdsPrivacyNetwork,
            source: .adblock,
            json: Self.exampleRuleJSON,
            contentHash: "adblock-hash"
        )

        let summary = ProtectionOverlapDiagnostics.summarize(
            [tracking, adblock],
            includeExpensiveDiagnostics: true
        )

        XCTAssertEqual(summary.exactCanonicalOverlapCount, 1)
        XCTAssertEqual(summary.domainResourceOverlapCount, 1)
        XCTAssertTrue(summary.exactComparisonAvailable)
        XCTAssertTrue(summary.notes.isEmpty)
    }

    func testOverlapDiagnosticsStayDeferredWithoutParsingPayloads() {
        let tracking = planned(
            identifier: "tracking-invalid",
            group: .trackingNetwork,
            source: .tracking,
            json: "{",
            contentHash: "tracking-hash"
        )
        let adblock = planned(
            identifier: "adblock-invalid",
            group: .adblockAdsPrivacyNetwork,
            source: .adblock,
            json: "{",
            contentHash: "adblock-hash"
        )

        XCTAssertEqual(
            ProtectionOverlapDiagnostics.summarize(
                [tracking, adblock],
                includeExpensiveDiagnostics: false
            ),
            .deferred
        )
    }

    private func planned(
        identifier: String,
        group: SumiProtectionGroupKind,
        source: ProtectionRuleSource,
        json: String,
        contentHash: String
    ) -> ProtectionPlannedRuleDefinition {
        ProtectionPlannedRuleDefinition(
            group: group,
            source: source,
            definition: SumiContentRuleListDefinition(
                name: identifier,
                encodedContentRuleList: json,
                storeIdentifierOverride: identifier,
                contentHashOverride: contentHash
            )
        )
    }

    private static let exampleRuleJSON =
        """
        [
          {
            "trigger": { "url-filter": "https://example.com/path" },
            "action": { "type": "block" }
          }
        ]
        """

    private static let otherRuleJSON =
        """
        [
          {
            "trigger": { "url-filter": "https://other.test/path" },
            "action": { "type": "block" }
          }
        ]
        """
}
