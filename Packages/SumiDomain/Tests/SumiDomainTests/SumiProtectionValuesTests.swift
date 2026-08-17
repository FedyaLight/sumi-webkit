@testable import SumiDomain
import XCTest

final class SumiProtectionValuesTests: XCTestCase {
    func testProtectionLevelAndGroupKindsRoundTripTheirStableRawValues() throws {
        let levels = try JSONDecoder().decode(
            [SumiProtectionLevel].self,
            from: JSONEncoder().encode(SumiProtectionLevel.allCases)
        )
        XCTAssertEqual(levels, [.off, .adblock])
        XCTAssertEqual(SumiProtectionLevel.off.requestedGroups, [])
        XCTAssertEqual(
            SumiProtectionLevel.adblock.requestedGroups,
            [.adblockAdsPrivacyNetwork]
        )
    }

    func testAttachmentStateCanonicalizesCollectionOrder() {
        let state = SumiProtectionAttachmentState(
            siteHost: "example.com",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [.adblockAdsPrivacyNetwork],
            attachedRuleListIdentifiers: ["tracking", "ads"]
        )

        XCTAssertEqual(state.activeGroups, [.adblockAdsPrivacyNetwork])
        XCTAssertEqual(state.attachedRuleListIdentifiers, ["ads", "tracking"])
        XCTAssertTrue(state.isEnabled)
    }

    func testEffectiveAttachmentIdentityTreatsRuleListsAsASet() {
        let first = SumiProtectionAttachmentState(
            siteHost: "a.example",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [
                .adblockAdsPrivacyNetwork,
                .adblockAdsPrivacyNetwork,
            ],
            attachedRuleListIdentifiers: ["tracking", "ads", "tracking"]
        )
        let reversed = SumiProtectionAttachmentState(
            siteHost: "b.example",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [
                .adblockAdsPrivacyNetwork,
            ],
            attachedRuleListIdentifiers: ["ads", "tracking"]
        )

        XCTAssertEqual(
            first.activeGroups,
            [.adblockAdsPrivacyNetwork]
        )
        XCTAssertEqual(first.attachedRuleListIdentifiers, ["ads", "tracking"])
        XCTAssertTrue(first.hasSameEffectiveWebViewAttachment(as: reversed))
    }

    func testDisabledAttachmentAndReloadRequirementRemainPureValues() {
        let state = SumiProtectionAttachmentState.disabled(
            siteHost: "example.com",
            requestedLevel: .adblock
        )
        let requirement = SumiProtectionReloadRequirement(
            siteHost: "example.com",
            desiredAttachmentState: state
        )

        XCTAssertFalse(state.isEnabled)
        XCTAssertEqual(state.requestedLevel, .adblock)
        XCTAssertEqual(state.effectiveLevel, .off)
        XCTAssertEqual(requirement.desiredAttachmentState, state)
    }

    func testEffectiveWebViewAttachmentIgnoresSiteAndDiagnosticMetadata() {
        let first = SumiProtectionAttachmentState(
            siteHost: "a.example",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [.adblockAdsPrivacyNetwork],
            attachedRuleListIdentifiers: ["tracking"],
            activeGenerationId: "generation-a"
        )
        let second = SumiProtectionAttachmentState(
            siteHost: "b.example",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [.adblockAdsPrivacyNetwork],
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

    func testEnabledAdvancedAttachmentDoesNotMatchDisabledWhenBothHaveNoRuleLists() {
        let enabled = SumiProtectionAttachmentState(
            siteHost: "enabled.example",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [.adblockAdsPrivacyNetwork]
        )

        XCTAssertFalse(
            enabled.hasSameEffectiveWebViewAttachment(
                as: .disabled(
                    siteHost: "disabled.example",
                    requestedLevel: .adblock
                )
            )
        )
    }
}
