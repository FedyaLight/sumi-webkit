import XCTest
@testable import SumiDomain

final class SumiProtectionValuesTests: XCTestCase {
    func testProtectionLevelAndGroupKindsRoundTripTheirStableRawValues() throws {
        let levels = try JSONDecoder().decode(
            [SumiProtectionLevel].self,
            from: JSONEncoder().encode(SumiProtectionLevel.allCases)
        )
        XCTAssertEqual(levels, [.off, .protection, .adblock])
        XCTAssertEqual(SumiProtectionLevel.off.requestedGroups, [])
        XCTAssertEqual(SumiProtectionLevel.protection.requestedGroups, [.trackingNetwork])
        XCTAssertEqual(
            SumiProtectionLevel.adblock.requestedGroups,
            [.trackingNetwork, .adblockAdsPrivacyNetwork]
        )
        XCTAssertEqual(SumiProtectionGroupKind.cosmetic.rawValue, "cosmetic")
    }

    func testAttachmentStateCanonicalizesCollectionOrder() {
        let state = SumiProtectionAttachmentState(
            siteHost: "example.com",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [.trackingNetwork, .adblockAdsPrivacyNetwork],
            attachedRuleListIdentifiers: ["tracking", "ads"]
        )

        XCTAssertEqual(state.activeGroups, [.adblockAdsPrivacyNetwork, .trackingNetwork])
        XCTAssertEqual(state.attachedRuleListIdentifiers, ["ads", "tracking"])
        XCTAssertTrue(state.isEnabled)
    }

    func testEffectiveAttachmentIdentityTreatsRuleListsAsASet() {
        let first = SumiProtectionAttachmentState(
            siteHost: "a.example",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [
                .trackingNetwork,
                .adblockAdsPrivacyNetwork,
                .trackingNetwork,
            ],
            attachedRuleListIdentifiers: ["tracking", "ads", "tracking"]
        )
        let reversed = SumiProtectionAttachmentState(
            siteHost: "b.example",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [
                .adblockAdsPrivacyNetwork,
                .trackingNetwork,
            ],
            attachedRuleListIdentifiers: ["ads", "tracking"]
        )

        XCTAssertEqual(
            first.activeGroups,
            [.adblockAdsPrivacyNetwork, .trackingNetwork]
        )
        XCTAssertEqual(first.attachedRuleListIdentifiers, ["ads", "tracking"])
        XCTAssertTrue(first.hasSameEffectiveWebViewAttachment(as: reversed))
    }

    func testDisabledAttachmentAndReloadRequirementRemainPureValues() {
        let state = SumiProtectionAttachmentState.disabled(
            siteHost: "example.com",
            requestedLevel: .protection
        )
        let requirement = SumiProtectionReloadRequirement(
            siteHost: "example.com",
            desiredAttachmentState: state
        )

        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.requestedLevel, .protection)
        XCTAssertEqual(state.effectiveLevel, .off)
        XCTAssertEqual(requirement.desiredAttachmentState, state)
    }

    func testEffectiveWebViewAttachmentIgnoresSiteAndDiagnosticMetadata() {
        let first = SumiProtectionAttachmentState(
            siteHost: "a.example",
            requestedLevel: .protection,
            effectiveLevel: .protection,
            activeGroups: [.trackingNetwork],
            attachedRuleListIdentifiers: ["tracking"],
            activeGenerationId: "generation-a"
        )
        let second = SumiProtectionAttachmentState(
            siteHost: "b.example",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [.adblockAdsPrivacyNetwork, .trackingNetwork],
            attachedRuleListIdentifiers: ["tracking"],
            activeGenerationId: "generation-b"
        )

        XCTAssertTrue(
            first.hasSameEffectiveWebViewAttachment(as: second)
        )
        XCTAssertFalse(
            first.hasSameEffectiveWebViewAttachment(
                as: .disabled(siteHost: "b.example")
            )
        )
    }
}
