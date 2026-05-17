import CryptoKit
import XCTest

@testable import Sumi

@MainActor
final class SumiProtectionCoordinatorTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testProtectionLevelPersistsAndMigratesLegacySettings() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }

        let cleanSettings = SumiProtectionSettings(userDefaults: harness.defaults)
        XCTAssertEqual(cleanSettings.level, .off)

        cleanSettings.setLevel(.extreme)
        XCTAssertEqual(SumiProtectionSettings(userDefaults: harness.defaults).level, .extreme)

        let legacyTrackingHarness = TestDefaultsHarness()
        defer { legacyTrackingHarness.reset() }
        legacyTrackingHarness.defaults.set(true, forKey: "settings.modules.trackingProtection.enabled")
        XCTAssertEqual(SumiProtectionSettings(userDefaults: legacyTrackingHarness.defaults).level, .protection)

        let legacyAdblockHarness = TestDefaultsHarness()
        defer { legacyAdblockHarness.reset() }
        legacyAdblockHarness.defaults.set(true, forKey: "settings.modules.adBlocking.enabled")
        XCTAssertEqual(SumiProtectionSettings(userDefaults: legacyAdblockHarness.defaults).level, .adblock)
    }

    func testProtectionLevelMapsToProductGroupsAndBundleProfiles() {
        XCTAssertEqual(SumiProtectionLevel.off.requestedGroups, [])
        XCTAssertEqual(SumiProtectionLevel.protection.requestedGroups, [.trackingNetwork])
        XCTAssertEqual(SumiProtectionLevel.adblock.requestedGroups, [.trackingNetwork, .adblockAdsPrivacyNetwork])
        XCTAssertEqual(SumiProtectionLevel.extreme.requestedGroups, [.trackingNetwork, .maximumNativeNetwork, .maximumNativeCSS])

        XCTAssertNil(SumiProtectionLevel.off.preferredBundleProfileId)
        XCTAssertNil(SumiProtectionLevel.protection.preferredBundleProfileId)
        XCTAssertEqual(SumiProtectionLevel.adblock.preferredBundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(SumiProtectionLevel.extreme.preferredBundleProfileId, "maximumCustomReference")

        XCTAssertEqual(SumiProtectionLevel.adblock.adblockRuleGroupKinds, [.network])
        XCTAssertEqual(SumiProtectionLevel.extreme.adblockRuleGroupKinds, [.network, .nativeCosmeticCSS])
    }

    func testOffAttachesNoRuleListsAndDoesNoRuntimeWork() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "tracking", filter: ".*tracker\\.example/.*")]
        )

        fixture.coordinator.setLevel(.off)
        let decision = fixture.coordinator.normalTabDecision(
            for: URL(string: "https://example.com")!,
            profileId: nil
        )

        XCTAssertEqual(decision.plan.requestedLevel, .off)
        XCTAssertEqual(decision.plan.effectiveLevel, .off)
        XCTAssertTrue(decision.plan.activeGroups.isEmpty)
        XCTAssertTrue(decision.plan.expectedRuleListIdentifiers.isEmpty)
        XCTAssertNil(decision.contentBlockingService)
        XCTAssertEqual(fixture.trackingRuleSource.ruleListCallCount, 0)
        XCTAssertFalse(fixture.didCreateAdblockRuleListStore())
        XCTAssertFalse(fixture.adBlockingModule.hasLoadedRuntime)
    }

    func testStrictOffApplyAndStartupDoNotRestorePreparedBundles() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryAdblockDirectory()
        let generatedRoot = temporaryAdblockDirectory()
        try makePreparedBundle(
            at: generatedRoot
                .appendingPathComponent("adguardAdsPrivacy", isDirectory: true)
                .appendingPathComponent("SumiAdblockBundle", isDirectory: true),
            profileId: "adguardAdsPrivacy",
            generationId: "adguard-off-generation",
            includeNativeCSS: false
        )
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")],
            preparedBundleResourceURL: resourceRoot,
            preparedBundleGeneratedRootURL: generatedRoot
        )

        fixture.coordinator.setLevel(.off)
        _ = try await fixture.coordinator.applySelectedLevel()
        let restoredManifest = try await fixture.coordinator.restoreAppliedLevelForStartup()
        let decision = fixture.coordinator.normalTabDecision(
            for: URL(string: "https://example.com/off")!,
            profileId: nil
        )
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertNil(restoredManifest)
        XCTAssertEqual(decision.plan.effectiveLevel, .off)
        XCTAssertTrue(decision.plan.activeGroups.isEmpty)
        XCTAssertTrue(decision.plan.expectedRuleListIdentifiers.isEmpty)
        XCTAssertNil(decision.contentBlockingService)
        XCTAssertNil(global.bundleProfileId)
        XCTAssertNil(global.activeGenerationId)
        XCTAssertTrue(global.globalGroupsAvailable.isEmpty)
        XCTAssertFalse(fixture.didCreateAdblockRuleListStore())
        XCTAssertEqual(fixture.trackingRuleSource.ruleListCallCount, 0)
        XCTAssertFalse(fixture.adBlockingModule.hasLoadedRuntime)
    }

    func testStandardPlanDefersExpensiveOverlapDiagnosticsUntilDiagnosticsRequest() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = try await makeCoordinatorFixtureWithSeededAdblockBundle(
            defaults: harness.defaults,
            level: .adblock,
            bundleProfileId: "adguardAdsPrivacy",
            networkRules: [Self.ruleList(identifier: "sumi.adblock.network.curated", filter: ".*ads\\.example/.*")]
        )
        let url = URL(string: "https://example.com")!
        let standardPlan = try await waitForPlan(fixture.coordinator) { plan in
            plan.bundleProfileId == "adguardAdsPrivacy"
        }

        XCTAssertEqual(standardPlan.overlapSummary, .deferred)

        let diagnosticsPlan = fixture.coordinator.rulePlan(
            for: url,
            profileId: nil,
            includeExpensiveDiagnostics: true
        )
        XCTAssertNotEqual(diagnosticsPlan.overlapSummary, .deferred)
        XCTAssertTrue(diagnosticsPlan.overlapSummary.exactComparisonAvailable)
    }

    func testSelectingProtectionRequiresApplyBeforeTrackingGroupActivates() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")]
        )

        fixture.coordinator.setLevel(.protection)
        XCTAssertTrue(fixture.coordinator.applyNeeded)
        XCTAssertEqual(
            fixture.coordinator.normalTabDecision(
                for: URL(string: "https://example.com")!,
                profileId: nil
            ).plan.effectiveLevel,
            .off
        )

        _ = try await fixture.coordinator.applySelectedLevel()
        let decision = fixture.coordinator.normalTabDecision(
            for: URL(string: "https://example.com")!,
            profileId: nil
        )

        XCTAssertFalse(fixture.coordinator.applyNeeded)
        XCTAssertEqual(decision.plan.effectiveLevel, .protection)
        XCTAssertEqual(decision.plan.activeGroups, [.trackingNetwork])
        XCTAssertEqual(decision.plan.expectedRuleListIdentifiers, ["sumi.tracking.network"])
        XCTAssertTrue(decision.plan.trackingGroupActive)
        XCTAssertFalse(decision.plan.adblockGroupActive)
        XCTAssertFalse(decision.plan.nativeCSSGroupActive)
        XCTAssertNotNil(decision.contentBlockingService)
        XCTAssertEqual(fixture.trackingRuleSource.ruleListCallCount, 1)
        XCTAssertFalse(fixture.didCreateAdblockRuleListStore())
    }

    func testAdblockAttachesTrackingAndCuratedNetworkBundleOnly() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = try await makeCoordinatorFixtureWithSeededAdblockBundle(
            defaults: harness.defaults,
            level: .adblock,
            bundleProfileId: "adguardAdsPrivacy",
            generationSource: .embeddedBundle,
            previousGenerationId: "previous-adblock-generation",
            networkRules: [Self.ruleList(identifier: "sumi.adblock.network.curated", filter: ".*ads\\.example/.*")]
        )

        let outcome = try await fixture.coordinator.applySelectedLevel()
        let plan = try await waitForPlan(fixture.coordinator) { plan in
            plan.bundleProfileId == "adguardAdsPrivacy"
        }

        XCTAssertEqual(plan.effectiveLevel, .adblock)
        XCTAssertEqual(plan.activeGroups, [.adblockAdsPrivacyNetwork, .trackingNetwork])
        XCTAssertEqual(plan.bundleSource, .embeddedBundle)
        XCTAssertEqual(plan.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(plan.requiredBundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(outcome.installedBundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(plan.previousGenerationId, "previous-adblock-generation")
        XCTAssertTrue(plan.previousGenerationRetained)
        XCTAssertTrue(plan.trackingGroupActive)
        XCTAssertTrue(plan.adblockGroupActive)
        XCTAssertFalse(plan.nativeCSSGroupActive)
        XCTAssertEqual(plan.shardCountsByGroup[.adblockAdsPrivacyNetwork], 1)
        XCTAssertTrue(plan.expectedRuleListIdentifiers.contains("sumi.tracking.network"))
        XCTAssertTrue(plan.expectedRuleListIdentifiers.contains("sumi.adblock.network.curated"))
    }

    func testExtremeAttachesTrackingMaximumNetworkAndNativeCSSBundle() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = try await makeCoordinatorFixtureWithSeededAdblockBundle(
            defaults: harness.defaults,
            level: .extreme,
            bundleProfileId: "maximumCustomReference",
            generationSource: .developmentBundle,
            networkRules: [Self.ruleList(identifier: "sumi.adblock.network.maximum", filter: ".*ads\\.example/.*")],
            nativeCSSRules: [Self.ruleList(identifier: "sumi.adblock.nativeCSS.maximum", filter: ".*", selector: ".ad")]
        )

        let outcome = try await fixture.coordinator.applySelectedLevel()
        let plan = try await waitForPlan(fixture.coordinator) { plan in
            plan.bundleProfileId == "maximumCustomReference"
        }

        XCTAssertEqual(plan.effectiveLevel, .extreme)
        XCTAssertEqual(plan.activeGroups, [.maximumNativeCSS, .maximumNativeNetwork, .trackingNetwork])
        XCTAssertEqual(plan.bundleSource, .developmentBundle)
        XCTAssertEqual(plan.bundleProfileId, "maximumCustomReference")
        XCTAssertEqual(plan.requiredBundleProfileId, "maximumCustomReference")
        XCTAssertEqual(outcome.installedBundleProfileId, "maximumCustomReference")
        XCTAssertTrue(plan.trackingGroupActive)
        XCTAssertTrue(plan.adblockGroupActive)
        XCTAssertTrue(plan.nativeCSSGroupActive)
        XCTAssertEqual(plan.shardCountsByGroup[.maximumNativeNetwork], 1)
        XCTAssertEqual(plan.shardCountsByGroup[.maximumNativeCSS], 1)
    }

    func testLiveApplyTransitionsPublishCachedAttachmentPlanWithoutRestart() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryAdblockDirectory()
        let generatedRoot = temporaryAdblockDirectory()
        try makePreparedBundle(
            at: generatedRoot
                .appendingPathComponent("adguardAdsPrivacy", isDirectory: true)
                .appendingPathComponent("SumiAdblockBundle", isDirectory: true),
            profileId: "adguardAdsPrivacy",
            generationId: "adguard-live-generation",
            includeNativeCSS: false
        )
        try makePreparedBundle(
            at: generatedRoot
                .appendingPathComponent("maximumCustomReference", isDirectory: true)
                .appendingPathComponent("SumiAdblockBundle", isDirectory: true),
            profileId: "maximumCustomReference",
            generationId: "maximum-live-generation",
            includeNativeCSS: true
        )
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")],
            preparedBundleResourceURL: resourceRoot,
            preparedBundleGeneratedRootURL: generatedRoot
        )
        let url = URL(string: "https://example.com/live-switch")!

        func apply(
            _ level: SumiProtectionLevel,
            expectedEffectiveLevel: SumiProtectionLevel,
            expectedGroups: [SumiProtectionGroupKind],
            expectedIdentifierPrefixes: [String],
            expectsService: Bool,
            file: StaticString = #filePath,
            line: UInt = #line
        ) async throws {
            fixture.coordinator.setLevel(level)
            _ = try await fixture.coordinator.applySelectedLevel()
            let callCountAfterApply = fixture.trackingRuleSource.ruleListCallCount
            let decision = fixture.coordinator.normalTabDecision(for: url, profileId: nil)
            let secondDecision = fixture.coordinator.normalTabDecision(for: url, profileId: nil)

            XCTAssertEqual(decision.plan.effectiveLevel, expectedEffectiveLevel, file: file, line: line)
            XCTAssertEqual(decision.plan.activeGroups, expectedGroups, file: file, line: line)
            for prefix in expectedIdentifierPrefixes {
                XCTAssertTrue(
                    decision.plan.expectedRuleListIdentifiers.contains { $0.hasPrefix(prefix) },
                    file: file,
                    line: line
                )
            }
            XCTAssertEqual(decision.contentBlockingService != nil, expectsService, file: file, line: line)
            XCTAssertEqual(secondDecision.contentBlockingService != nil, expectsService, file: file, line: line)
            XCTAssertEqual(fixture.trackingRuleSource.ruleListCallCount, callCountAfterApply, file: file, line: line)
        }

        try await apply(
            .adblock,
            expectedEffectiveLevel: .adblock,
            expectedGroups: [.adblockAdsPrivacyNetwork, .trackingNetwork],
            expectedIdentifierPrefixes: ["sumi.tracking.network", "sumi.adblock.network.adguard-live-generation.0001"],
            expectsService: true
        )
        try await apply(
            .off,
            expectedEffectiveLevel: .off,
            expectedGroups: [],
            expectedIdentifierPrefixes: [],
            expectsService: false
        )
        let offDiagnostics = fixture.coordinator.currentTabDiagnostics(
            for: url,
            appliedState: .disabled(siteHost: "example.com"),
            reloadRequired: false,
            actualAttachedRuleListIdentifiers: []
        )
        XCTAssertEqual(offDiagnostics.effectiveProtectionLevel, .off)
        XCTAssertTrue(offDiagnostics.activeGroups.isEmpty)
        XCTAssertTrue(offDiagnostics.expectedRuleListIdentifiers.isEmpty)
        XCTAssertTrue(offDiagnostics.actualAttachedRuleListIdentifiers.isEmpty)
        XCTAssertTrue(offDiagnostics.missingRuleListIdentifiers.isEmpty)
        XCTAssertNil(offDiagnostics.bundleProfileId)

        try await apply(
            .protection,
            expectedEffectiveLevel: .protection,
            expectedGroups: [.trackingNetwork],
            expectedIdentifierPrefixes: ["sumi.tracking.network"],
            expectsService: true
        )
        try await apply(
            .adblock,
            expectedEffectiveLevel: .adblock,
            expectedGroups: [.adblockAdsPrivacyNetwork, .trackingNetwork],
            expectedIdentifierPrefixes: ["sumi.tracking.network", "sumi.adblock.network.adguard-live-generation.0001"],
            expectsService: true
        )
        try await apply(
            .extreme,
            expectedEffectiveLevel: .extreme,
            expectedGroups: [.maximumNativeCSS, .maximumNativeNetwork, .trackingNetwork],
            expectedIdentifierPrefixes: [
                "sumi.tracking.network",
                "sumi.adblock.network.maximum-live-generation.0001",
                "sumi.adblock.nativeCSS.maximum-live-generation.0001",
            ],
            expectsService: true
        )
        try await apply(
            .protection,
            expectedEffectiveLevel: .protection,
            expectedGroups: [.trackingNetwork],
            expectedIdentifierPrefixes: ["sumi.tracking.network"],
            expectsService: true
        )
    }

    func testMissingRequiredBundleApplyReportsClearErrorWithoutRuntimeGeneratedFallback() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryAdblockDirectory()
        let generatedRoot = temporaryAdblockDirectory()
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")],
            preparedBundleResourceURL: resourceRoot,
            preparedBundleGeneratedRootURL: generatedRoot
        )

        fixture.coordinator.setLevel(.protection)
        _ = try await fixture.coordinator.applySelectedLevel()
        fixture.coordinator.setLevel(.adblock)
        do {
            _ = try await fixture.coordinator.applySelectedLevel()
            XCTFail("Expected applying Adblock without a prepared bundle to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Required prepared bundle profile adguardAdsPrivacy is unavailable"))
            XCTAssertTrue(error.localizedDescription.contains(resourceRoot.path))
            XCTAssertTrue(error.localizedDescription.contains(generatedRoot.path))
            XCTAssertTrue(error.localizedDescription.contains("exists=false"))
            XCTAssertTrue(error.localizedDescription.contains("Path does not exist"))
        }
        let plan = fixture.coordinator.rulePlan(
            for: URL(string: "https://example.com")!,
            profileId: nil
        )
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertEqual(plan.requestedLevel, .protection)
        XCTAssertEqual(plan.effectiveLevel, .protection)
        XCTAssertEqual(global.selectedProtectionLevel, .adblock)
        XCTAssertEqual(global.appliedProtectionLevel, .protection)
        XCTAssertEqual(global.requiredBundleProfileId, "adguardAdsPrivacy")
        XCTAssertTrue(global.applyNeeded)
        XCTAssertTrue(global.lastApplyError?.contains("Required prepared bundle profile adguardAdsPrivacy is unavailable") == true)
        XCTAssertFalse(global.preparedBundleAvailable)
        XCTAssertNil(global.preparedBundleSource)
        XCTAssertEqual(global.searchedBundlePaths.map(\.source), [.appResource, .developmentBundle, .futureRemoteBundle])
        XCTAssertNil(plan.bundleSource)
        XCTAssertFalse(global.lastApplyError?.contains("runtimeGenerated") == true)

        fixture.coordinator.setLevel(.extreme)
        do {
            _ = try await fixture.coordinator.applySelectedLevel()
            XCTFail("Expected applying Extreme without a prepared bundle to fail")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Required prepared bundle profile maximumCustomReference is unavailable"))
            XCTAssertFalse(error.localizedDescription.contains("runtimeGenerated"))
        }

        let extremeFailureGlobal = fixture.coordinator.globalDiagnostics()
        XCTAssertEqual(extremeFailureGlobal.selectedProtectionLevel, .extreme)
        XCTAssertEqual(extremeFailureGlobal.appliedProtectionLevel, .protection)
        XCTAssertEqual(extremeFailureGlobal.requiredBundleProfileId, "maximumCustomReference")
        XCTAssertFalse(extremeFailureGlobal.preparedBundleAvailable)
        XCTAssertTrue(extremeFailureGlobal.lastApplyError?.contains("maximumCustomReference") == true)
    }

    func testApplyAdblockDiscoversDevelopmentBundleAndPublishesActiveGeneration() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryAdblockDirectory()
        let generatedRoot = temporaryAdblockDirectory()
        let bundleURL = generatedRoot
            .appendingPathComponent("adguardAdsPrivacy", isDirectory: true)
            .appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try makePreparedBundle(
            at: bundleURL,
            profileId: "adguardAdsPrivacy",
            generationId: "adguard-dev-generation",
            includeNativeCSS: false
        )
        let nativeCompiler = RecordingPreparedBundleNativeCompiler()
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")],
            preparedBundleResourceURL: resourceRoot,
            preparedBundleGeneratedRootURL: generatedRoot,
            nativeCompiler: nativeCompiler,
            enhancedCompiler: nativeCompiler
        )

        fixture.coordinator.setLevel(.adblock)
        let outcome = try await fixture.coordinator.applySelectedLevel()
        let plan = fixture.coordinator.rulePlan(for: URL(string: "https://example.com")!, profileId: nil)
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertEqual(outcome.installedBundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(plan.bundleSource, .developmentBundle)
        XCTAssertEqual(plan.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(plan.activeGenerationId, "adguard-dev-generation")
        XCTAssertEqual(plan.activeGroups, [.adblockAdsPrivacyNetwork, .trackingNetwork])
        XCTAssertEqual(global.generationSource, .developmentBundle)
        XCTAssertEqual(global.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(global.activeGenerationId, "adguard-dev-generation")
        XCTAssertTrue(global.adblockBundleAvailable)
        XCTAssertTrue(global.preparedBundleAvailable)
        XCTAssertEqual(global.preparedBundleSource, .developmentBundle)
        XCTAssertNil(global.lastApplyError)
        let compileCount = await nativeCompiler.compileCount()
        XCTAssertEqual(compileCount, 0)
    }

    func testApplyExtremeDiscoversDevelopmentBundle() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryAdblockDirectory()
        let generatedRoot = temporaryAdblockDirectory()
        let bundleURL = generatedRoot
            .appendingPathComponent("maximumCustomReference", isDirectory: true)
            .appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try makePreparedBundle(
            at: bundleURL,
            profileId: "maximumCustomReference",
            generationId: "maximum-dev-generation",
            includeNativeCSS: true
        )
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")],
            preparedBundleResourceURL: resourceRoot,
            preparedBundleGeneratedRootURL: generatedRoot
        )

        fixture.coordinator.setLevel(.extreme)
        let outcome = try await fixture.coordinator.applySelectedLevel()
        let plan = fixture.coordinator.rulePlan(for: URL(string: "https://example.com")!, profileId: nil)
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertEqual(outcome.installedBundleProfileId, "maximumCustomReference")
        XCTAssertEqual(plan.bundleSource, .developmentBundle)
        XCTAssertEqual(plan.bundleProfileId, "maximumCustomReference")
        XCTAssertEqual(plan.activeGroups, [.maximumNativeCSS, .maximumNativeNetwork, .trackingNetwork])
        XCTAssertEqual(global.preparedBundleSource, .developmentBundle)
        XCTAssertEqual(global.bundleProfileId, "maximumCustomReference")
        XCTAssertNil(global.lastApplyError)
    }

    func testColdStartWithAppliedAdblockRestoresPreparedManifestBeforeNormalTabPlan() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let settings = SumiProtectionSettings(userDefaults: harness.defaults)
        settings.setLevel(.adblock)
        settings.setAppliedLevel(.adblock)
        let trackingSource = RecordingTrackingRuleSource(definitions: [
            Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*"),
        ])
        let trackingModule = makeTrackingModule(
            registry: registry,
            defaults: harness.defaults,
            trackingRuleSource: trackingSource
        )
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: temporaryAdblockDirectory())
        try await seedManifest(
            in: manifestStore,
            bundleProfileId: "adguardAdsPrivacy",
            generationSource: .embeddedBundle,
            previousGenerationId: nil,
            networkRules: [
                Self.ruleList(
                    identifier: "sumi.adblock.network.cold-start",
                    filter: ".*ads\\.example/.*"
                ),
            ],
            nativeCSSRules: []
        )
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { AdblockSettingsStore(userDefaults: harness.defaults) },
            sitePolicyFactory: { AdblockSitePolicyStore(userDefaults: harness.defaults) },
            ruleListStoreFactory: { settings, isEnabled in
                AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler(),
                    embeddedBundleURLProvider: { nil }
                )
            }
        )
        let coordinator = SumiProtectionCoordinator(
            settings: settings,
            trackingProtectionModule: trackingModule,
            adBlockingModule: adBlockingModule,
            moduleRegistry: registry
        )

        _ = try await coordinator.restoreAppliedLevelForStartup()
        let decision = coordinator.normalTabDecision(
            for: URL(string: "https://example.com/cold-start")!,
            profileId: nil
        )

        XCTAssertEqual(decision.plan.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(decision.plan.activeGroups, [.adblockAdsPrivacyNetwork, .trackingNetwork])
        XCTAssertTrue(decision.plan.expectedRuleListIdentifiers.contains("sumi.adblock.network.cold-start"))
        XCTAssertEqual(coordinator.globalDiagnostics().lastApplyError, nil)
        XCTAssertEqual(coordinator.globalDiagnostics().lastApplySummary, "Restored Adblock using prepared bundle adguardAdsPrivacy.")
    }

    func testApplyPrefersAppResourceBundleWhenBothSourcesExist() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryAdblockDirectory()
        let generatedRoot = temporaryAdblockDirectory()
        let appBundleURL = resourceRoot
            .appendingPathComponent("SumiAdblockBundles/adguardAdsPrivacy", isDirectory: true)
            .appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        let developmentBundleURL = generatedRoot
            .appendingPathComponent("adguardAdsPrivacy", isDirectory: true)
            .appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try makePreparedBundle(
            at: appBundleURL,
            profileId: "adguardAdsPrivacy",
            generationId: "adguard-app-resource-generation",
            includeNativeCSS: false
        )
        try makePreparedBundle(
            at: developmentBundleURL,
            profileId: "adguardAdsPrivacy",
            generationId: "adguard-development-generation",
            includeNativeCSS: false
        )
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")],
            preparedBundleResourceURL: resourceRoot,
            preparedBundleGeneratedRootURL: generatedRoot
        )

        fixture.coordinator.setLevel(.adblock)
        _ = try await fixture.coordinator.applySelectedLevel()
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertEqual(global.preparedBundleSource, .appResource)
        XCTAssertEqual(global.generationSource, .embeddedBundle)
        XCTAssertEqual(global.activeGenerationId, "adguard-app-resource-generation")
    }

    func testSuccessfulPreparedBundleApplyClearsStaleApplyError() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryAdblockDirectory()
        let generatedRoot = temporaryAdblockDirectory()
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")],
            preparedBundleResourceURL: resourceRoot,
            preparedBundleGeneratedRootURL: generatedRoot
        )

        fixture.coordinator.setLevel(.adblock)
        do {
            _ = try await fixture.coordinator.applySelectedLevel()
            XCTFail("Expected Adblock apply to fail before the bundle exists")
        } catch {
            XCTAssertNotNil(fixture.coordinator.globalDiagnostics().lastApplyError)
        }

        let bundleURL = generatedRoot
            .appendingPathComponent("adguardAdsPrivacy", isDirectory: true)
            .appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try makePreparedBundle(
            at: bundleURL,
            profileId: "adguardAdsPrivacy",
            generationId: "adguard-retry-generation",
            includeNativeCSS: false
        )
        _ = try await fixture.coordinator.applySelectedLevel()

        let global = fixture.coordinator.globalDiagnostics()
        XCTAssertNil(global.lastApplyError)
        XCTAssertEqual(global.lastApplySummary, "Applied Adblock using prepared bundle adguardAdsPrivacy.")
        XCTAssertEqual(global.activeGenerationId, "adguard-retry-generation")
    }

    func testRuntimeGeneratedBundleDoesNotSatisfyPreparedAdblockRequirement() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = try await makeCoordinatorFixtureWithSeededAdblockBundle(
            defaults: harness.defaults,
            level: .adblock,
            bundleProfileId: "adguardAdsPrivacy",
            generationSource: .runtimeGenerated,
            networkRules: [Self.ruleList(identifier: "sumi.adblock.network.runtime", filter: ".*ads\\.example/.*")]
        )

        XCTAssertTrue(fixture.coordinator.applyNeeded)
        let plan = fixture.coordinator.rulePlan(
            for: URL(string: "https://example.com")!,
            profileId: nil
        )
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertEqual(plan.bundleSource, .runtimeGenerated)
        XCTAssertEqual(plan.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertFalse(plan.activeGroups.contains(.adblockAdsPrivacyNetwork))
        XCTAssertTrue(plan.planningErrors.contains("Required prepared bundle profile adguardAdsPrivacy is not active."))
        XCTAssertFalse(global.adblockBundleAvailable)
        XCTAssertTrue(global.applyNeeded)
    }

    func testSuccessfulApplyClearsStaleApplyError() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryAdblockDirectory()
        let generatedRoot = temporaryAdblockDirectory()
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")],
            preparedBundleResourceURL: resourceRoot,
            preparedBundleGeneratedRootURL: generatedRoot
        )

        fixture.coordinator.setLevel(.adblock)
        do {
            _ = try await fixture.coordinator.applySelectedLevel()
            XCTFail("Expected Adblock apply to fail without a prepared bundle")
        } catch {
            XCTAssertTrue(fixture.coordinator.globalDiagnostics().lastApplyError?.contains("adguardAdsPrivacy") == true)
        }

        fixture.coordinator.setLevel(.protection)
        _ = try await fixture.coordinator.applySelectedLevel()

        let global = fixture.coordinator.globalDiagnostics()
        XCTAssertNil(global.lastApplyError)
        XCTAssertEqual(global.appliedProtectionLevel, .protection)
        XCTAssertEqual(global.lastApplySummary, "Applied Protection.")
    }

    func testCachedRulePlanDoesNotLoadRuleDefinitionsDuringUIRendering() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = try await makeCoordinatorFixtureWithSeededAdblockBundle(
            defaults: harness.defaults,
            level: .adblock,
            bundleProfileId: "adguardAdsPrivacy",
            generationSource: .embeddedBundle,
            networkRules: [Self.ruleList(identifier: "sumi.adblock.network.curated", filter: ".*ads\\.example/.*")]
        )
        XCTAssertEqual(fixture.trackingRuleSource.ruleListCallCount, 0)

        let cachedPlan = fixture.coordinator.cachedRulePlan(
            for: URL(string: "https://example.com")!,
            profileId: nil
        )
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertEqual(cachedPlan.effectiveLevel, .adblock)
        XCTAssertEqual(cachedPlan.activeGroups, [.adblockAdsPrivacyNetwork, .trackingNetwork])
        XCTAssertEqual(cachedPlan.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertTrue(cachedPlan.ruleDefinitions.isEmpty)
        XCTAssertEqual(cachedPlan.expectedRuleListIdentifiers, ["sumi.adblock.network.curated"])
        XCTAssertEqual(fixture.trackingRuleSource.ruleListCallCount, 0)
        XCTAssertTrue(global.trackingSourceAvailable)
        XCTAssertFalse(fixture.trackingRuleSource.ruleListCallCount > 0)
    }

    func testPerSiteDisableDisablesAllProtectionGroups() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = try await makeCoordinatorFixtureWithSeededAdblockBundle(
            defaults: harness.defaults,
            level: .adblock,
            bundleProfileId: "adguardAdsPrivacy",
            networkRules: [Self.ruleList(identifier: "sumi.adblock.network.curated", filter: ".*ads\\.example/.*")]
        )
        try await waitForPlan(fixture.coordinator) { $0.bundleProfileId == "adguardAdsPrivacy" }

        let url = URL(string: "https://www.example.com/path")!
        fixture.coordinator.setSiteOverride(.disabled, for: url)
        let plan = fixture.coordinator.rulePlan(for: url, profileId: nil)

        XCTAssertEqual(plan.siteHost, "example.com")
        XCTAssertEqual(plan.siteOverride, .disabled)
        XCTAssertFalse(plan.sitePolicyAllowsProtection)
        XCTAssertEqual(plan.effectiveLevel, .off)
        XCTAssertTrue(plan.activeGroups.isEmpty)
        XCTAssertTrue(plan.expectedRuleListIdentifiers.isEmpty)
    }

    func testInternalSurfacesAreIneligibleAndAttachNothing() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")]
        )

        fixture.coordinator.setLevel(.protection)
        _ = try await fixture.coordinator.applySelectedLevel()
        let plan = fixture.coordinator.rulePlan(
            for: SumiSurface.settingsSurfaceURL(paneQuery: "privacy"),
            profileId: nil
        )

        XCTAssertEqual(plan.ineligibleSurfaceReason, "Internal Sumi surface")
        XCTAssertEqual(plan.effectiveLevel, .off)
        XCTAssertTrue(plan.activeGroups.isEmpty)
        XCTAssertTrue(plan.expectedRuleListIdentifiers.isEmpty)
        XCTAssertNil(fixture.coordinator.normalTabDecision(for: SumiSurface.settingsSurfaceURL(paneQuery: "privacy"), profileId: nil).contentBlockingService)
    }

    func testAttachmentPlanRemovesDuplicateIdentifiersAndCanonicalCrossSourceRules() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let duplicateJSON = Self.encodedRules(filter: "https?://shared.example/.*")
        let fixture = try await makeCoordinatorFixtureWithSeededAdblockBundle(
            defaults: harness.defaults,
            level: .adblock,
            bundleProfileId: "adguardAdsPrivacy",
            trackingDefinitions: [
                SumiContentRuleListDefinition(
                    name: "tracking-shared",
                    encodedContentRuleList: duplicateJSON,
                    storeIdentifierOverride: "sumi.tracking.shared"
                ),
                Self.ruleList(identifier: "sumi.tracking.identifier-duplicate", filter: ".*identifier\\.example/.*"),
            ],
            networkRules: [
                SumiContentRuleListDefinition(
                    name: "adblock-shared",
                    encodedContentRuleList: duplicateJSON,
                    storeIdentifierOverride: "sumi.adblock.shared"
                ),
                Self.ruleList(identifier: "sumi.tracking.identifier-duplicate", filter: ".*different\\.example/.*"),
                Self.ruleList(identifier: "sumi.adblock.network.unique", filter: ".*ads\\.example/.*"),
            ]
        )

        _ = try await waitForPlan(fixture.coordinator) { plan in
            plan.bundleProfileId == "adguardAdsPrivacy"
                && plan.dedupeSummary.inputRuleListCount == 5
        }
        let plan = fixture.coordinator.rulePlan(
            for: URL(string: "https://example.com")!,
            profileId: nil,
            includeExpensiveDiagnostics: true
        )

        XCTAssertEqual(plan.dedupeSummary.inputRuleListCount, 5)
        XCTAssertEqual(plan.dedupeSummary.finalRuleListCount, 3)
        XCTAssertEqual(plan.dedupeSummary.duplicateIdentifierCountRemoved, 1)
        XCTAssertEqual(plan.dedupeSummary.duplicateCanonicalJSONCountRemoved, 1)
        XCTAssertEqual(plan.expectedRuleListIdentifiers.count, Set(plan.expectedRuleListIdentifiers).count)
        XCTAssertFalse(plan.expectedRuleListIdentifiers.contains("sumi.adblock.shared"))
        XCTAssertTrue(plan.overlapSummary.exactComparisonAvailable)
        XCTAssertTrue(plan.overlapSummary.reportLine.contains("exactCanonicalOverlap="))
        XCTAssertEqual(plan.overlapSummary.domainResourceOverlapCount, 1)
    }

    func testDiagnosticsReportsMissingUnexpectedIdentifiersAndCoreFields() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = try await makeCoordinatorFixtureWithSeededAdblockBundle(
            defaults: harness.defaults,
            level: .adblock,
            bundleProfileId: "adguardAdsPrivacy",
            generationSource: .embeddedBundle,
            networkRules: [Self.ruleList(identifier: "sumi.adblock.network.curated", filter: ".*ads\\.example/.*")]
        )
        let plan = try await waitForPlan(fixture.coordinator) { $0.bundleProfileId == "adguardAdsPrivacy" }
        let diagnostics = fixture.coordinator.currentTabDiagnostics(
            for: URL(string: "https://example.com")!,
            appliedState: SumiProtectionAttachmentState(
                siteHost: "example.com",
                requestedLevel: .adblock,
                effectiveLevel: .adblock,
                activeGroups: [.trackingNetwork, .adblockAdsPrivacyNetwork],
                attachedRuleListIdentifiers: ["sumi.adblock.old.identifier"],
                activeGenerationId: "old"
            ),
            reloadRequired: true,
            actualAttachedRuleListIdentifiers: ["sumi.adblock.old.identifier"],
            contentBlockingAssetSummary: SumiNormalTabContentBlockingAssetSummary(
                isInstalled: true,
                globalRuleListCount: 1,
                updateRuleCount: 2,
                isContentBlockingFeatureEnabled: true,
                globalRuleListIdentifiers: ["sumi.adblock.old.identifier"],
                lookupSucceededIdentifiers: ["sumi.tracking.network"],
                lookupFailedIdentifiers: ["sumi.adblock.network.curated"],
                addedToUserContentControllerIdentifiers: ["sumi.adblock.old.identifier"]
            )
        )

        XCTAssertEqual(diagnostics.protectionLevel, .adblock)
        XCTAssertEqual(diagnostics.effectiveProtectionLevel, .adblock)
        XCTAssertEqual(diagnostics.generationSource, .embeddedBundle)
        XCTAssertEqual(diagnostics.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(diagnostics.activeGroups, plan.activeGroups)
        XCTAssertEqual(diagnostics.missingRuleListIdentifiers, plan.expectedRuleListIdentifiers)
        XCTAssertEqual(diagnostics.missingAfterAttachmentIdentifiers, plan.expectedRuleListIdentifiers)
        XCTAssertEqual(diagnostics.lookupSucceededIdentifiers, ["sumi.tracking.network"])
        XCTAssertEqual(diagnostics.lookupFailedIdentifiers, ["sumi.adblock.network.curated"])
        XCTAssertEqual(diagnostics.addedToUserContentControllerIdentifiers, ["sumi.adblock.old.identifier"])
        XCTAssertEqual(diagnostics.appliedProtectionGenerationId, "old")
        XCTAssertEqual(diagnostics.appliedProtectionGroups, [.adblockAdsPrivacyNetwork, .trackingNetwork])
        XCTAssertEqual(diagnostics.unexpectedOldRuleListIdentifiers, ["sumi.adblock.old.identifier"])
        XCTAssertTrue(diagnostics.reloadRequired)
        XCTAssertEqual(diagnostics.reloadRequiredReason, "protection attachment plan changed")
        XCTAssertFalse(diagnostics.didManualReloadRebuildWebView)
        XCTAssertFalse(diagnostics.appliedAfterManualReload)
        XCTAssertNotNil(diagnostics.contentBlockingServiceGenerationId)
        XCTAssertGreaterThanOrEqual(diagnostics.planComputeDuration, 0)
        XCTAssertTrue(diagnostics.developerReport.contains("protectionLevel=adblock"))
        XCTAssertTrue(diagnostics.developerReport.contains("lookupSucceededIdentifiers=sumi.tracking.network"))
        XCTAssertTrue(diagnostics.developerReport.contains("addedToUserContentControllerIdentifiers=sumi.adblock.old.identifier"))
        XCTAssertTrue(diagnostics.developerReport.contains("didManualReloadRebuildWebView=false"))
        XCTAssertTrue(diagnostics.developerReport.contains("dedupeSummary="))
        XCTAssertTrue(diagnostics.developerReport.contains("overlapSummary="))
    }

    func testSettingsPagePlanCanBeIneligibleWhileGlobalDiagnosticsStillShowSelectedAdblock() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = try await makeCoordinatorFixtureWithSeededAdblockBundle(
            defaults: harness.defaults,
            level: .adblock,
            bundleProfileId: "adguardAdsPrivacy",
            generationSource: .embeddedBundle,
            networkRules: [Self.ruleList(identifier: "sumi.adblock.network.curated", filter: ".*ads\\.example/.*")]
        )
        _ = try await waitForPlan(fixture.coordinator) { $0.bundleProfileId == "adguardAdsPrivacy" }

        let settingsURL = SumiSurface.settingsSurfaceURL(paneQuery: "privacy")
        let pagePlan = fixture.coordinator.rulePlan(for: settingsURL, profileId: nil)
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertEqual(global.selectedProtectionLevel, .adblock)
        XCTAssertEqual(global.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertFalse(global.applyNeeded)
        XCTAssertEqual(pagePlan.ineligibleSurfaceReason, "Internal Sumi surface")
        XCTAssertEqual(pagePlan.effectiveLevel, .off)
        XCTAssertTrue(pagePlan.activeGroups.isEmpty)
    }

    func testCopyDiagnosticsSeparatesGlobalStateFromTargetPagePlan() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = try await makeCoordinatorFixtureWithSeededAdblockBundle(
            defaults: harness.defaults,
            level: .adblock,
            bundleProfileId: "adguardAdsPrivacy",
            generationSource: .embeddedBundle,
            networkRules: [Self.ruleList(identifier: "sumi.adblock.network.curated", filter: ".*ads\\.example/.*")]
        )
        _ = try await waitForPlan(fixture.coordinator) { $0.bundleProfileId == "adguardAdsPrivacy" }

        let report = fixture.coordinator.copyDiagnosticsReport(
            for: SumiSurface.settingsSurfaceURL(paneQuery: "privacy"),
            currentTabDiagnostics: nil,
            targetDescription: "current tab (ineligible: Internal Sumi surface)"
        )

        XCTAssertTrue(report.contains("Global protection state"))
        XCTAssertTrue(report.contains("protectionLevel=adblock"))
        XCTAssertTrue(report.contains("bundleProfileId=adguardAdsPrivacy"))
        XCTAssertTrue(report.contains("Target page plan"))
        XCTAssertTrue(report.contains("targetURL=sumi://settings?pane=privacy"))
        XCTAssertTrue(report.contains("ineligibleSurfaceReason=Internal Sumi surface"))
        XCTAssertTrue(report.contains("effectiveProtectionLevel=off"))
    }

    func testUnifiedDiagnosticsTargetUsesLastEligibleWebTabWhenSettingsIsSelected() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults)
        )
        let settings = SumiProtectionSettings(userDefaults: harness.defaults)
        settings.setLevel(.protection)
        let trackingModule = makeTrackingModule(
            registry: registry,
            defaults: harness.defaults,
            trackingRuleSource: RecordingTrackingRuleSource(
                definitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")]
            )
        )
        let coordinator = SumiProtectionCoordinator(
            settings: settings,
            trackingProtectionModule: trackingModule,
            adBlockingModule: SumiAdBlockingModule(moduleRegistry: registry),
            moduleRegistry: registry
        )
        _ = try await coordinator.applySelectedLevel()
        let browserManager = BrowserManager(
            moduleRegistry: registry,
            trackingProtectionModule: trackingModule,
            protectionCoordinator: coordinator
        )
        let windowState = BrowserWindowState()
        let space = browserManager.tabManager.currentSpace
        windowState.currentSpaceId = space?.id
        let webTab = browserManager.tabManager.createNewTab(
            url: "https://www.example.com/failing-page",
            in: space,
            activate: false
        )
        let settingsTab = browserManager.tabManager.createNewTab(
            url: SumiSurface.settingsSurfaceURL(paneQuery: "privacy").absoluteString,
            in: space,
            activate: false
        )
        windowState.currentTabId = settingsTab.id
        if let spaceId = space?.id {
            windowState.recentRegularTabIdsBySpace[spaceId] = [settingsTab.id, webTab.id]
        }

        let target = browserManager.lastActiveProtectionEligibleNormalWebTab(
            in: windowState,
            excluding: settingsTab
        )
        let report = coordinator.copyDiagnosticsReport(
            for: target?.url,
            currentTabDiagnostics: nil,
            targetDescription: "last eligible web tab (current tab ineligible: Internal Sumi surface)",
            requestingURL: settingsTab.url
        )

        XCTAssertEqual(target?.id, webTab.id)
        XCTAssertTrue(report.contains("targetSource=last eligible web tab"))
        XCTAssertTrue(report.contains("targetURL=https://www.example.com/failing-page"))
        XCTAssertTrue(report.contains("requestingURL=sumi://settings?pane=privacy"))
        XCTAssertFalse(report.contains("targetURL=sumi://settings"))
    }

    func testUnifiedSourceKeepsNativeModesScriptFreeAndEnhancedRuntimeSeparate() throws {
        let coordinatorSource = try Self.source(named: "Sumi/ContentBlocking/SumiProtectionCoordinator.swift")
        let tabRuntimeSource = try Self.source(named: "Sumi/Models/Tab/Tab+WebViewRuntime.swift")
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        XCTAssertFalse(coordinatorSource.contains("WKUserScript"))
        XCTAssertFalse(coordinatorSource.contains("WKWebExtension"))
        XCTAssertFalse(coordinatorSource.contains("MutationObserver"))
        XCTAssertTrue(coordinatorSource.contains("preparedBundleProfileId"))
        XCTAssertTrue(coordinatorSource.contains("isPreparedBundleSource"))
        XCTAssertFalse(coordinatorSource.contains("compileNativeContentBlocking"))
        XCTAssertTrue(tabRuntimeSource.contains("protectionCoordinator"))
        XCTAssertTrue(tabRuntimeSource.contains(".normalTabDecision(for: url, profileId: profile.id)"))
        XCTAssertFalse(tabRuntimeSource.contains("additionalContentBlockingServices: [adBlockingDecision"))
        XCTAssertFalse(tabRuntimeSource.contains("normalTabContentBlockingDecision("))
        XCTAssertTrue(tabRuntimeSource.contains("normalTabEnhancedRuntimeScripts"))
        XCTAssertTrue(settingsSource.contains("DEBUG Legacy Protection Controls"))
        XCTAssertTrue(settingsSource.contains("Adblock & Protection"))
        XCTAssertTrue(settingsSource.contains("Apply selected protection level"))
        XCTAssertTrue(settingsSource.contains("Deprecated runtime-generated dev profile"))
        XCTAssertTrue(settingsSource.contains("#if DEBUG"))
    }

    func testSettingsAndURLHubUseCachedProtectionPlansForNormalRendering() throws {
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")
        let urlHubSource = try Self.source(named: "Sumi/Components/Sidebar/URLBarHubPopover.swift")

        XCTAssertTrue(settingsSource.contains("coordinator.cachedRulePlan(for: currentTab?.url"))
        XCTAssertTrue(settingsSource.contains("coordinator.cachedRulePlan(for: diagnosticsTarget.url"))
        XCTAssertFalse(settingsSource.contains("coordinator.rulePlan(for: currentTab?.url"))
        XCTAssertFalse(settingsSource.contains("coordinator.rulePlan(for: diagnosticsTarget.url"))
        XCTAssertTrue(urlHubSource.contains("protectionCoordinator.cachedRulePlan(for: url"))
        XCTAssertFalse(urlHubSource.contains("protectionCoordinator.rulePlan(for: url"))
    }

    private struct CoordinatorFixture {
        let coordinator: SumiProtectionCoordinator
        let trackingRuleSource: RecordingTrackingRuleSource
        let adBlockingModule: SumiAdBlockingModule
        let didCreateAdblockRuleListStore: () -> Bool
    }

    private func makeCoordinatorFixture(
        defaults: UserDefaults,
        trackingDefinitions: [SumiContentRuleListDefinition],
        preparedBundleResourceURL: URL? = nil,
        preparedBundleGeneratedRootURL: URL? = nil,
        nativeCompiler: NativeContentBlockingCompiler? = nil,
        enhancedCompiler: EnhancedCompatibilityCompiler? = nil
    ) -> CoordinatorFixture {
        let settings = SumiProtectionSettings(userDefaults: defaults)
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        let trackingSource = RecordingTrackingRuleSource(definitions: trackingDefinitions)
        let trackingModule = makeTrackingModule(
            registry: registry,
            defaults: defaults,
            trackingRuleSource: trackingSource
        )
        var didCreateAdblockRuleListStore = false
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { AdblockSettingsStore(userDefaults: defaults) },
            sitePolicyFactory: { AdblockSitePolicyStore(userDefaults: defaults) },
            preparedBundleResourceURL: preparedBundleResourceURL,
            preparedBundleGeneratedRootURL: preparedBundleGeneratedRootURL,
            ruleListStoreFactory: { settings, isEnabled in
                didCreateAdblockRuleListStore = true
                return AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    nativeCompiler: nativeCompiler,
                    enhancedCompiler: enhancedCompiler,
                    embeddedBundleURLProvider: { nil }
                )
            }
        )
        let coordinator = SumiProtectionCoordinator(
            settings: settings,
            trackingProtectionModule: trackingModule,
            adBlockingModule: adBlockingModule,
            moduleRegistry: registry
        )
        return CoordinatorFixture(
            coordinator: coordinator,
            trackingRuleSource: trackingSource,
            adBlockingModule: adBlockingModule,
            didCreateAdblockRuleListStore: { didCreateAdblockRuleListStore }
        )
    }

    private func makeCoordinatorFixtureWithSeededAdblockBundle(
        defaults: UserDefaults,
        level: SumiProtectionLevel,
        bundleProfileId: String,
        generationSource: AdblockRuleGenerationSource = .embeddedBundle,
        previousGenerationId: String? = nil,
        trackingDefinitions: [SumiContentRuleListDefinition]? = nil,
        networkRules: [SumiContentRuleListDefinition],
        nativeCSSRules: [SumiContentRuleListDefinition] = []
    ) async throws -> CoordinatorFixture {
        let settings = SumiProtectionSettings(userDefaults: defaults)
        settings.setLevel(level)
        settings.setAppliedLevel(level)
        let registry = SumiModuleRegistry(
            settingsStore: SumiModuleSettingsStore(userDefaults: defaults)
        )
        registry.setEnabled(true, for: .trackingProtection)
        registry.setEnabled(true, for: .adBlocking)
        let resolvedTrackingDefinitions = trackingDefinitions ?? [
            SumiContentRuleListDefinition(
                name: "tracking-network",
                encodedContentRuleList: Self.encodedRules(filter: ".*tracker\\.example/.*"),
                storeIdentifierOverride: "sumi.tracking.network"
            ),
        ]
        let trackingSource = RecordingTrackingRuleSource(definitions: resolvedTrackingDefinitions)
        let trackingModule = makeTrackingModule(
            registry: registry,
            defaults: defaults,
            trackingRuleSource: trackingSource
        )
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: temporaryAdblockDirectory())
        try await seedManifest(
            in: manifestStore,
            bundleProfileId: bundleProfileId,
            generationSource: generationSource,
            previousGenerationId: previousGenerationId,
            networkRules: networkRules,
            nativeCSSRules: nativeCSSRules
        )
        var didCreateAdblockRuleListStore = false
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { AdblockSettingsStore(userDefaults: defaults) },
            sitePolicyFactory: { AdblockSitePolicyStore(userDefaults: defaults) },
            ruleListStoreFactory: { settings, isEnabled in
                didCreateAdblockRuleListStore = true
                return AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: manifestStore,
                    compiler: SumiWKContentRuleListCompiler(),
                    embeddedBundleURLProvider: { nil }
                )
            }
        )
        _ = adBlockingModule.normalTabDecision(for: URL(string: "https://example.com")!)
        try await waitForActiveManifest(adBlockingModule, profileId: bundleProfileId)
        let coordinator = SumiProtectionCoordinator(
            settings: settings,
            trackingProtectionModule: trackingModule,
            adBlockingModule: adBlockingModule,
            moduleRegistry: registry
        )
        return CoordinatorFixture(
            coordinator: coordinator,
            trackingRuleSource: trackingSource,
            adBlockingModule: adBlockingModule,
            didCreateAdblockRuleListStore: { didCreateAdblockRuleListStore }
        )
    }

    private func makeTrackingModule(
        registry: SumiModuleRegistry,
        defaults: UserDefaults,
        trackingRuleSource: RecordingTrackingRuleSource
    ) -> SumiTrackingProtectionModule {
        SumiTrackingProtectionModule(
            moduleRegistry: registry,
            settingsFactory: {
                SumiTrackingProtectionSettings(userDefaults: defaults)
            },
            dataStoreFactory: {
                SumiTrackingProtectionDataStore(
                    userDefaults: defaults,
                    storageDirectory: self.temporaryTrackingDirectory()
                )
            },
            contentBlockingAssetsFactory: { settings, dataStore in
                let provider = SumiTrackingRuleListProvider(
                    settings: settings,
                    dataStore: dataStore,
                    trackingRuleSource: trackingRuleSource
                )
                return SumiTrackingContentBlockingAssets(
                    ruleListProvider: provider,
                    contentBlockingService: SumiContentBlockingService(policy: .disabled)
                )
            }
        )
    }

    private func seedManifest(
        in store: AdblockUpdateManifestStore,
        bundleProfileId: String,
        generationSource: AdblockRuleGenerationSource,
        previousGenerationId: String?,
        networkRules: [SumiContentRuleListDefinition],
        nativeCSSRules: [SumiContentRuleListDefinition]
    ) async throws {
        let generationId = "\(bundleProfileId)-test-generation"
        let networkShards = networkRules.enumerated().map { index, definition in
            Self.shard(
                id: "network-\(index)",
                generationId: generationId,
                kind: .network,
                definition: definition
            )
        }
        let nativeCSSShards = nativeCSSRules.enumerated().map { index, definition in
            Self.shard(
                id: "nativeCSS-\(index)",
                generationId: generationId,
                kind: .nativeCosmeticCSS,
                definition: definition
            )
        }
        let manifest = AdblockCompiledGenerationManifest(
            schemaVersion: 1,
            activeGenerationId: generationId,
            createdDate: Date(),
            selectedFilterLists: [
                AdblockCompiledGenerationManifest.SelectedFilterList(
                    id: bundleProfileId,
                    displayName: bundleProfileId,
                    contentHash: bundleProfileId
                ),
            ],
            networkShards: networkShards,
            nativeCSSShards: nativeCSSShards,
            enhancedRuntimeBundle: nil,
            nativeProfile: nil,
            nativeCompiler: NativeContentBlockingCompilerIdentity(
                name: "adblock-rust",
                version: "test"
            ),
            nativeCompilerSourceLists: [],
            compilerDiagnosticsSummary: "test",
            lastSuccessfulUpdateDate: Date(),
            previousGenerationId: previousGenerationId,
            generationSource: generationSource,
            nativeRuleBundleId: "sumi.native.bundle.\(bundleProfileId).test",
            bundleProfileId: bundleProfileId
        )
        let stagingDirectory = try await store.beginStaging()
        var stagedCompiledShardURLs = [String: URL]()
        for (descriptor, definition) in zip(networkShards + nativeCSSShards, networkRules + nativeCSSRules) {
            let shardURL = stagingDirectory.appendingPathComponent("\(descriptor.id).json")
            try Data(definition.encodedContentRuleList.utf8).write(to: shardURL)
            stagedCompiledShardURLs[descriptor.id] = shardURL
        }
        try await store.commit(
            manifest: manifest,
            httpMetadata: [:],
            stagedRawListURLs: [:],
            stagedCompiledShardURLs: stagedCompiledShardURLs
        )
    }

    private func makePreparedBundle(
        at bundleURL: URL,
        profileId: String,
        generationId: String,
        includeNativeCSS: Bool
    ) throws {
        let networkURL = bundleURL.appendingPathComponent("network", isDirectory: true)
        try FileManager.default.createDirectory(at: networkURL, withIntermediateDirectories: true)
        let networkJSON = Self.encodedRules(filter: ".*ads\\.example/.*")
        let networkData = Data(networkJSON.utf8)
        let networkHash = Self.sha256Hex(networkData)
        try networkData.write(to: networkURL.appendingPathComponent("network-0001.json"))

        var shards: [[String: Any]] = [
            [
                "kind": "network",
                "group": "network",
                "relativePath": "network/network-0001.json",
                "hash": networkHash,
                "byteSize": networkData.count,
                "ruleCount": 1,
                "webKitIdentifier": "sumi.adblock.network.\(generationId).0001.\(networkHash.prefix(12))",
            ],
        ]

        if includeNativeCSS {
            let nativeCSSURL = bundleURL.appendingPathComponent("nativeCSS", isDirectory: true)
            try FileManager.default.createDirectory(at: nativeCSSURL, withIntermediateDirectories: true)
            let nativeCSSJSON = Self.encodedRules(filter: ".*", selector: ".ad-banner")
            let nativeCSSData = Data(nativeCSSJSON.utf8)
            let nativeCSSHash = Self.sha256Hex(nativeCSSData)
            try nativeCSSData.write(to: nativeCSSURL.appendingPathComponent("nativeCSS-0001.json"))
            shards.append(
                [
                    "kind": "nativeCSS",
                    "group": "nativeCSS",
                    "relativePath": "nativeCSS/nativeCSS-0001.json",
                    "hash": nativeCSSHash,
                    "byteSize": nativeCSSData.count,
                    "ruleCount": 1,
                    "webKitIdentifier": "sumi.adblock.nativeCSS.\(generationId).0001.\(nativeCSSHash.prefix(12))",
                ]
            )
        }

        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "bundleId": "sumi.adblock.bundle.\(profileId).test",
            "generationId": generationId,
            "profileId": profileId,
            "compiler": [
                "name": "adblock-rust",
                "version": "adblock-rust-adapter/0.1.0 adblock-rust/0.12.5 sumi-native-css-safety/0.4",
            ],
            "nativeCSSSafetyPolicyVersion": "sumi-native-css-safety/0.4",
            "generatedDate": "2026-05-17T00:00:00Z",
            "lists": [
                [
                    "id": profileId,
                    "displayName": profileId,
                    "url": "https://example.com/\(profileId).txt",
                    "hash": "\(profileId)-hash",
                    "byteSize": 24,
                    "ruleCount": shards.count,
                    "category": "baseAds",
                ],
            ],
            "shards": shards,
            "diagnosticsSummary": [
                "inputRuleCount": shards.count,
                "finalRuleCount": shards.count,
                "finalShardCount": shards.count,
                "networkRuleCount": 1,
                "nativeCSSRuleCount": includeNativeCSS ? 1 : 0,
                "unsafeCSSFilteredCount": 0,
                "warnings": [],
            ],
            "unsafeCSSFilteredCount": 0,
            "deduplication": [
                "inputRawRuleCount": shards.count,
                "rawDuplicateCountRemoved": 0,
                "nativeJSONDuplicateCountRemoved": 0,
                "skippedDedupeCount": 0,
                "skippedDedupeReasons": [String: Int](),
                "finalRuleCount": shards.count,
                "finalShardCount": shards.count,
            ],
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: bundleURL.appendingPathComponent("manifest.json"))
        try Data("{}".utf8).write(to: bundleURL.appendingPathComponent("diagnostics.json"))
    }

    private static func shard(
        id: String,
        generationId: String,
        kind: AdblockCompiledRuleGroupKind,
        definition: SumiContentRuleListDefinition
    ) -> NativeContentBlockingShardDescriptor {
        NativeContentBlockingShardDescriptor(
            id: id,
            generationId: generationId,
            kind: kind,
            sourceListIdentifiers: ["test"],
            sourceCategories: [.baseAds],
            webKitIdentifier: definition.storeIdentifierOverride ?? definition.name,
            contentHash: definition.contentHash,
            approximateRuleCount: 1,
            jsonByteCount: definition.encodedContentRuleList.utf8.count,
            compilerIdentity: NativeContentBlockingCompilerIdentity(
                name: "adblock-rust",
                version: "test"
            ),
            profileIdentity: nil,
            diagnosticsSummary: "test"
        )
    }

    private func waitForActiveManifest(
        _ module: SumiAdBlockingModule,
        profileId: String
    ) async throws {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if module.activeManifestIfLoaded()?.bundleProfileId == profileId {
                return
            }
            _ = module.normalTabDecision(for: URL(string: "https://example.com")!)
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTFail("Timed out waiting for active Adblock manifest \(profileId)")
    }

    private func waitForPlan(
        _ coordinator: SumiProtectionCoordinator,
        where predicate: (SumiProtectionRulePlan) -> Bool
    ) async throws -> SumiProtectionRulePlan {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            let plan = coordinator.rulePlan(
                for: URL(string: "https://example.com")!,
                profileId: nil
            )
            if predicate(plan) {
                return plan
            }
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        let plan = coordinator.rulePlan(for: URL(string: "https://example.com")!, profileId: nil)
        XCTFail("Timed out waiting for protection plan. Last plan: \(plan)")
        return plan
    }

    private func temporaryTrackingDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiProtectionTracking-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func temporaryAdblockDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiProtectionAdblock-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private static func ruleList(
        identifier: String,
        filter: String,
        selector: String? = nil
    ) -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: identifier,
            encodedContentRuleList: encodedRules(filter: filter, selector: selector),
            storeIdentifierOverride: identifier
        )
    }

    private static func encodedRules(filter: String, selector: String? = nil) -> String {
        let escapedFilter = jsonEscaped(filter)
        if let selector {
            let escapedSelector = jsonEscaped(selector)
            return """
            [
              {
                "trigger": {
                  "url-filter": "\(escapedFilter)"
                },
                "action": {
                  "type": "css-display-none",
                  "selector": "\(escapedSelector)"
                }
              }
            ]
            """
        }
        return """
        [
          {
            "trigger": {
              "url-filter": "\(escapedFilter)"
            },
            "action": {
              "type": "block"
            }
          }
        ]
        """
    }

    private static func jsonEscaped(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}

@MainActor
private final class RecordingTrackingRuleSource: SumiTrackingProtectionRuleProviding {
    private(set) var ruleListCallCount = 0
    private let definitions: [SumiContentRuleListDefinition]

    init(definitions: [SumiContentRuleListDefinition]) {
        self.definitions = definitions
    }

    func ruleLists(for policy: SumiTrackingProtectionPolicy) throws -> [SumiContentRuleListDefinition] {
        ruleListCallCount += 1
        return policy.isFullyDisabled ? [] : definitions
    }
}

private actor RecordingPreparedBundleNativeCompiler: NativeContentBlockingCompiler, EnhancedCompatibilityCompiler {
    nonisolated let identity = NativeContentBlockingCompilerIdentity(
        name: "recording-runtime-generation-boundary",
        version: "test"
    )

    private var calls = 0

    func compileCount() -> Int {
        calls
    }

    func compileNativeContentBlocking(
        _ input: AdblockCompilationInput
    ) async throws -> NativeContentBlockingCompilationOutput {
        calls += 1
        throw AdblockUpdateDiagnostics(summary: "Runtime native compiler should not run for prepared bundles")
    }

    func compileEnhancedCompatibility(
        _ input: AdblockCompilationInput
    ) async throws -> EnhancedCompatibilityCompilationOutput {
        calls += 1
        throw AdblockUpdateDiagnostics(summary: "Enhanced compiler should not run for prepared bundles")
    }
}
