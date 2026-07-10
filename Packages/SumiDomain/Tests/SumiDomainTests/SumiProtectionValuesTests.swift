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
}
