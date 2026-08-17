import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SumiProtectionRulePlannerTests: XCTestCase {
    func testDisabledSiteOverrideSuppressesGlobalAttachmentPlanForEligibleSite() {
        let planner = SumiProtectionRulePlanner()
        var globalPlanCallCount = 0
        var emptyPlanCallCount = 0

        let plan = planner.makeRulePlan(
            for: URL(string: "https://www.example.com/article"),
            requestedLevel: .adblock,
            activeManifest: nil,
            loadRuleDefinitions: false,
            siteOverrideProvider: { _ in .disabled },
            globalAttachmentPlanProvider: { level, _ in
                globalPlanCallCount += 1
                return Self.globalPlan(
                    level: level,
                    activeGroups: [.adblockAdsPrivacyNetwork],
                    expectedRuleListIdentifiers: ["sumi.adblock.network.1"]
                )
            },
            emptyGlobalAttachmentPlanProvider: { level, manifest in
                emptyPlanCallCount += 1
                XCTAssertNil(manifest)
                return Self.globalPlan(level: level)
            }
        )

        XCTAssertEqual(globalPlanCallCount, 0)
        XCTAssertEqual(emptyPlanCallCount, 1)
        XCTAssertEqual(plan.requestedLevel, .adblock)
        XCTAssertEqual(plan.effectiveLevel, .off)
        XCTAssertEqual(plan.siteHost, "example.com")
        XCTAssertFalse(plan.sitePolicyAllowsProtection)
        XCTAssertTrue(plan.activeGroups.isEmpty)
        XCTAssertTrue(plan.expectedRuleListIdentifiers.isEmpty)
    }

    func testIneligibleSurfaceDoesNotConsultSiteOverrideOrGlobalPlan() {
        let planner = SumiProtectionRulePlanner()
        var siteOverrideCallCount = 0
        var globalPlanCallCount = 0
        var emptyPlanCallCount = 0

        let plan = planner.makeRulePlan(
            for: URL(string: "sumi://history"),
            requestedLevel: .adblock,
            activeManifest: nil,
            loadRuleDefinitions: false,
            siteOverrideProvider: { _ in
                siteOverrideCallCount += 1
                return .disabled
            },
            globalAttachmentPlanProvider: { level, _ in
                globalPlanCallCount += 1
                return Self.globalPlan(
                    level: level,
                    activeGroups: [.adblockAdsPrivacyNetwork],
                    expectedRuleListIdentifiers: ["sumi.adblock.network.1"]
                )
            },
            emptyGlobalAttachmentPlanProvider: { level, manifest in
                emptyPlanCallCount += 1
                XCTAssertNil(manifest)
                return Self.globalPlan(level: level)
            }
        )

        XCTAssertEqual(siteOverrideCallCount, 0)
        XCTAssertEqual(globalPlanCallCount, 0)
        XCTAssertEqual(emptyPlanCallCount, 1)
        XCTAssertEqual(plan.requestedLevel, .adblock)
        XCTAssertEqual(plan.effectiveLevel, .off)
        XCTAssertNil(plan.siteHost)
        XCTAssertFalse(plan.sitePolicyAllowsProtection)
    }

    private static func globalPlan(
        level: SumiProtectionLevel,
        activeGroups: [SumiProtectionGroupKind] = [],
        expectedRuleListIdentifiers: [String] = []
    ) -> SumiProtectionGlobalAttachmentPlan {
        SumiProtectionGlobalAttachmentPlan(
            level: level,
            activeGroups: activeGroups,
            expectedRuleListIdentifiers: expectedRuleListIdentifiers,
            ruleDefinitions: [],
            bundleProfileId: nil,
            activeGenerationId: nil
        )
    }
}
