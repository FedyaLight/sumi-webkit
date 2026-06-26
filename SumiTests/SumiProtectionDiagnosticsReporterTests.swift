import XCTest

@testable import Sumi

@MainActor
final class SumiProtectionDiagnosticsReporterTests: XCTestCase {
    func testCurrentTabDiagnosticsReportsMissingAndUnexpectedProtectionRuleLists() {
        let plan = makeRulePlan(
            expectedRuleListIdentifiers: [
                "sumi.tracking.network.0001",
                "sumi.adblock.network.0001",
            ]
        )
        let appliedState = SumiProtectionAttachmentState(
            siteHost: "example.com",
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            activeGroups: [.trackingNetwork, .adblockAdsPrivacyNetwork],
            attachedRuleListIdentifiers: ["sumi.tracking.network.0001"],
            activeGenerationId: "applied-generation"
        )
        let assetSummary = SumiNormalTabContentBlockingAssetSummary(
            isInstalled: true,
            globalRuleListCount: 3,
            updateRuleCount: 2,
            isContentBlockingFeatureEnabled: true,
            globalRuleListIdentifiers: [
                "sumi.adblock.network.old",
                "sumi.tracking.network.0001",
                "third.party.rule",
            ],
            lookupSucceededIdentifiers: ["sumi.tracking.network.0001"],
            lookupFailedIdentifiers: ["sumi.adblock.network.0001"],
            addedToUserContentControllerIdentifiers: ["sumi.tracking.network.0001"],
            ruleListLookupDuration: 0.003,
            tabAttachmentDuration: 0.004
        )

        let diagnostics = SumiProtectionDiagnosticsReporter.currentTabDiagnostics(
            for: URL(string: "https://example.com/article"),
            appliedState: appliedState,
            reloadRequired: true,
            reloadRequiredReason: "desired=adblock",
            didManualReloadRebuildWebView: true,
            appliedAfterManualReload: false,
            actualAttachedRuleListIdentifiers: nil,
            contentBlockingAssetSummary: assetSummary,
            webViewRebuildDuration: 0.005,
            urlHubSummaryDuration: 0.006,
            plan: plan,
            planComputeDuration: 0.002,
            contentBlockingServiceGenerationId: 42,
            bundleLookupDuration: 0.001
        )

        XCTAssertEqual(diagnostics.missingRuleListIdentifiers, ["sumi.adblock.network.0001"])
        XCTAssertEqual(diagnostics.unexpectedOldRuleListIdentifiers, ["sumi.adblock.network.old"])
        XCTAssertEqual(diagnostics.lookupFailedIdentifiers, ["sumi.adblock.network.0001"])
        XCTAssertEqual(diagnostics.contentBlockingServiceGenerationId, 42)
        XCTAssertTrue(diagnostics.developerReport.contains("missingRuleListIdentifiers=sumi.adblock.network.0001"))
        XCTAssertTrue(diagnostics.developerReport.contains("bundleLookupDuration=1.000ms"))
    }

#if DEBUG
    func testCopyDiagnosticsReportRendersGlobalAndTargetSectionsDeterministically() {
        let plan = makeRulePlan(
            expectedRuleListIdentifiers: [
                "sumi.tracking.network.0001",
                "sumi.adblock.network.0001",
            ]
        )
        let global = SumiProtectionGlobalDiagnostics(
            selectedProtectionLevel: .adblock,
            appliedProtectionLevel: .protection,
            browserRestartRequired: true,
            generationSource: .remoteReleaseBundle,
            nativeRuleBundleId: "bundle-id",
            bundleProfileId: SumiProtectionBundleProfile.adblock,
            activeGenerationId: "generation-id",
            remoteReleaseVersion: "20260626T120000Z",
            remoteReleaseTag: "20260626T120000Z",
            remoteReleaseURL: "https://example.com/release",
            remoteManifestSignatureRequired: true,
            remoteManifestSignatureVerified: false,
            remoteSigningKeyId: "test-key",
            remoteSigningKeyVersion: 2,
            lastRemoteUpdateError: "network failed",
            lastSignatureError: "signature failed",
            downgradeRejected: true,
            bundleGeneratedDate: Date(timeIntervalSince1970: 10),
            lastSuccessfulBundleInstallDate: Date(timeIntervalSince1970: 20),
            requiredBundleProfileId: SumiProtectionBundleProfile.adblock,
            preparedBundleAvailable: false,
            preparedBundleSource: .remoteReleaseBundle,
            searchedBundlePaths: [
                SumiPreparedAdblockBundleSearchPath(
                    source: .remoteReleaseBundle,
                    path: "/tmp/protection-bundle",
                    exists: false,
                    rejectionReason: "missing"
                ),
            ],
            applyNeeded: true,
            lastApplySummary: "apply summary",
            lastApplyError: "apply error",
            globalGroupsAvailable: [.trackingNetwork],
            groupSourceDiagnostics: [
                .trackingNetwork: "tracking source",
                .adblockAdsPrivacyNetwork: "adblock source",
            ],
            trackingSourceAvailable: true,
            adblockBundleAvailable: false,
            strictOffActive: false
        )

        let report = SumiProtectionDiagnosticsReporter.copyDiagnosticsReport(
            global: global,
            plan: plan,
            url: URL(string: "https://example.com/article"),
            currentTabDiagnostics: nil,
            targetDescription: "unit-test tab",
            requestingURL: URL(string: "https://request.example"),
            contentBlockingServiceGenerationId: 7,
            bundleLookupDuration: 0.002,
            startupSnapshot: nil,
            timestamp: Date(timeIntervalSince1970: 0)
        )

        XCTAssertTrue(report.contains("timestamp=1970-01-01T00:00:00.000Z"))
        XCTAssertTrue(report.contains("targetSource=unit-test tab"))
        XCTAssertTrue(report.contains("preparedBundleSource=remoteReleaseBundle"))
        XCTAssertTrue(report.contains("searchedBundlePaths=remoteReleaseBundle:path=/tmp/protection-bundle;exists=false;rejected=missing"))
        XCTAssertTrue(report.contains("currentTabDiagnosticsAvailable=false"))
        XCTAssertTrue(report.contains("Sumi Adblock & Protection current-tab diagnostics\ncurrentTab=nil"))
    }
#endif

    private func makeRulePlan(
        expectedRuleListIdentifiers: [String]
    ) -> SumiProtectionRulePlan {
        SumiProtectionRulePlan(
            requestedLevel: .adblock,
            effectiveLevel: .adblock,
            siteHost: "example.com",
            siteOverride: .inherit,
            sitePolicyAllowsProtection: true,
            activeGroups: [.trackingNetwork, .adblockAdsPrivacyNetwork],
            inactiveGroups: [],
            bundleSource: .remoteReleaseBundle,
            nativeRuleBundleId: "bundle-id",
            bundleProfileId: SumiProtectionBundleProfile.adblock,
            requiredBundleProfileId: SumiProtectionBundleProfile.adblock,
            activeGenerationId: "generation-id",
            previousGenerationId: "previous-generation",
            previousGenerationRetained: true,
            ruleCountsByGroup: [
                .trackingNetwork: 1,
                .adblockAdsPrivacyNetwork: 2,
            ],
            shardCountsByGroup: [
                .trackingNetwork: 1,
                .adblockAdsPrivacyNetwork: 1,
            ],
            expectedRuleListIdentifiers: expectedRuleListIdentifiers.sorted(),
            dedupeSummary: .empty,
            overlapSummary: .deferred,
            ineligibleSurfaceReason: nil,
            planningErrors: [],
            ruleDefinitions: []
        )
    }
}
