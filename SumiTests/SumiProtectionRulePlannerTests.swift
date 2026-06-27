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
            includeExpensiveDiagnostics: false,
            loadRuleDefinitions: false,
            siteOverrideProvider: { _ in .disabled },
            globalAttachmentPlanProvider: { level, _, _ in
                globalPlanCallCount += 1
                return Self.globalPlan(
                    level: level,
                    activeGroups: [.trackingNetwork, .adblockAdsPrivacyNetwork],
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
        XCTAssertEqual(plan.siteOverride, .disabled)
        XCTAssertFalse(plan.sitePolicyAllowsProtection)
        XCTAssertTrue(plan.activeGroups.isEmpty)
        XCTAssertTrue(plan.inactiveGroups.isEmpty)
        XCTAssertTrue(plan.expectedRuleListIdentifiers.isEmpty)
    }

    func testIneligibleSurfaceDoesNotConsultSiteOverrideOrGlobalPlan() {
        let planner = SumiProtectionRulePlanner()
        var siteOverrideCallCount = 0
        var globalPlanCallCount = 0
        var emptyPlanCallCount = 0

        let plan = planner.makeRulePlan(
            for: URL(string: "sumi://settings/privacy"),
            requestedLevel: .protection,
            activeManifest: nil,
            includeExpensiveDiagnostics: false,
            loadRuleDefinitions: false,
            siteOverrideProvider: { _ in
                siteOverrideCallCount += 1
                return .disabled
            },
            globalAttachmentPlanProvider: { level, _, _ in
                globalPlanCallCount += 1
                return Self.globalPlan(
                    level: level,
                    activeGroups: [.trackingNetwork],
                    expectedRuleListIdentifiers: ["sumi.tracking.network.1"]
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
        XCTAssertEqual(plan.requestedLevel, .protection)
        XCTAssertEqual(plan.effectiveLevel, .off)
        XCTAssertNil(plan.siteHost)
        XCTAssertEqual(plan.siteOverride, .inherit)
        XCTAssertFalse(plan.sitePolicyAllowsProtection)
        XCTAssertEqual(plan.ineligibleSurfaceReason, "Internal Sumi surface")
    }

    private static func globalPlan(
        level: SumiProtectionLevel,
        activeGroups: [SumiProtectionGroupKind] = [],
        expectedRuleListIdentifiers: [String] = []
    ) -> SumiProtectionGlobalAttachmentPlan {
        SumiProtectionGlobalAttachmentPlan(
            level: level,
            activeGroups: activeGroups,
            inactiveGroups: level.requestedGroups.filter { !activeGroups.contains($0) },
            ruleCountsByGroup: [:],
            shardCountsByGroup: [:],
            expectedRuleListIdentifiers: expectedRuleListIdentifiers,
            dedupeSummary: .empty,
            overlapSummary: .deferred,
            planningErrors: [],
            ruleDefinitions: [],
            bundleSource: nil,
            nativeRuleBundleId: nil,
            bundleProfileId: nil,
            requiredBundleProfileId: level.preferredBundleProfileId,
            activeGenerationId: nil,
            previousGenerationId: nil,
            previousGenerationRetained: false
        )
    }
}
