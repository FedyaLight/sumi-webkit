import Combine
import XCTest

@testable import Sumi

final class SumiURLHubPermissionsSubmenuTests: XCTestCase {
    func testProtectionRowShowsCurrentSiteStateAndDisclosure() {
        let row = SiteControlsSettingRowModel(
            id: "adblock-protection",
            chromeIconName: nil,
            fallbackSystemName: "shield.lefthalf.filled",
            title: "Adblock & Protection",
            subtitle: "Adblock on for this site",
            kind: .protection(
                plan: SumiProtectionRulePlan(
                    requestedLevel: .adblock,
                    effectiveLevel: .adblock,
                    siteHost: "example.com",
                    siteOverride: .inherit,
                    sitePolicyAllowsProtection: true,
                    activeGroups: [.trackingNetwork, .adblockAdsPrivacyNetwork],
                    inactiveGroups: [],
                    bundleSource: nil,
                    nativeRuleBundleId: "bundle",
                    bundleProfileId: SumiProtectionBundleProfile.adblock,
                    requiredBundleProfileId: SumiProtectionBundleProfile.adblock,
                    activeGenerationId: "generation",
                    previousGenerationId: nil,
                    previousGenerationRetained: false,
                    ruleCountsByGroup: [:],
                    shardCountsByGroup: [:],
                    expectedRuleListIdentifiers: ["sumi.adblock.network.1"],
                    dedupeSummary: .empty,
                    overlapSummary: .deferred,
                    ineligibleSurfaceReason: nil,
                    planningErrors: [],
                    ruleDefinitions: []
                ),
                reloadRequired: false
            )
        )

        XCTAssertTrue(row.isInteractive)
        XCTAssertFalse(row.isDisabled)
        XCTAssertTrue(row.showsDisclosure)
    }

    @MainActor
    func testPermissionEventSnapshotReadsDoNotPublishChanges() {
        let store = SumiPermissionIndicatorEventStore()
        let now = Date()
        store.record(
            SumiPermissionIndicatorEventRecord(
                id: "expired-notification",
                tabId: "tab-a",
                pageId: "tab-a:1",
                displayDomain: "example.com",
                permissionTypes: [.notifications],
                category: .blockedEvent,
                visualStyle: .blocked,
                priority: .blockedNotification,
                createdAt: now.addingTimeInterval(-20),
                expiresAt: now.addingTimeInterval(-10)
            )
        )

        var changeCount = 0
        let cancellable = store.objectWillChange.sink {
            changeCount += 1
        }

        XCTAssertTrue(store.recordsSnapshot(forPageId: "tab-a:1", now: now).isEmpty)
        XCTAssertEqual(changeCount, 0)
        cancellable.cancel()
    }
}
