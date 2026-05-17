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

    func testProtectionAttachesOnlyTrackingGroupAndDoesNotCreateAdblockRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")]
        )

        fixture.coordinator.setLevel(.protection)
        let decision = fixture.coordinator.normalTabDecision(
            for: URL(string: "https://example.com")!,
            profileId: nil
        )

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

        let plan = try await waitForPlan(fixture.coordinator) { plan in
            plan.bundleProfileId == "adguardAdsPrivacy"
        }

        XCTAssertEqual(plan.effectiveLevel, .adblock)
        XCTAssertEqual(plan.activeGroups, [.adblockAdsPrivacyNetwork, .trackingNetwork])
        XCTAssertEqual(plan.bundleSource, .embeddedBundle)
        XCTAssertEqual(plan.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(plan.requiredBundleProfileId, "adguardAdsPrivacy")
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

        let plan = try await waitForPlan(fixture.coordinator) { plan in
            plan.bundleProfileId == "maximumCustomReference"
        }

        XCTAssertEqual(plan.effectiveLevel, .extreme)
        XCTAssertEqual(plan.activeGroups, [.maximumNativeCSS, .maximumNativeNetwork, .trackingNetwork])
        XCTAssertEqual(plan.bundleSource, .developmentBundle)
        XCTAssertEqual(plan.bundleProfileId, "maximumCustomReference")
        XCTAssertEqual(plan.requiredBundleProfileId, "maximumCustomReference")
        XCTAssertTrue(plan.trackingGroupActive)
        XCTAssertTrue(plan.adblockGroupActive)
        XCTAssertTrue(plan.nativeCSSGroupActive)
        XCTAssertEqual(plan.shardCountsByGroup[.maximumNativeNetwork], 1)
        XCTAssertEqual(plan.shardCountsByGroup[.maximumNativeCSS], 1)
    }

    func testMissingRequiredBundleIsReportedWithoutRuntimeGeneratedFallback() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")]
        )

        fixture.coordinator.setLevel(.adblock)
        let plan = fixture.coordinator.rulePlan(
            for: URL(string: "https://example.com")!,
            profileId: nil
        )

        XCTAssertEqual(plan.requestedLevel, .adblock)
        XCTAssertEqual(plan.effectiveLevel, .protection)
        XCTAssertEqual(plan.requiredBundleProfileId, "adguardAdsPrivacy")
        XCTAssertTrue(plan.planningErrors.contains { $0.contains("Required native bundle profile adguardAdsPrivacy is not active") })
        XCTAssertNil(plan.bundleSource)
        XCTAssertFalse(plan.planningErrors.contains { $0.contains("runtimeGenerated") })
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

    func testInternalSurfacesAreIneligibleAndAttachNothing() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = makeCoordinatorFixture(
            defaults: harness.defaults,
            trackingDefinitions: [Self.ruleList(identifier: "sumi.tracking.network", filter: ".*tracker\\.example/.*")]
        )

        fixture.coordinator.setLevel(.protection)
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
                attachedRuleListIdentifiers: ["old.identifier"],
                activeGenerationId: "old"
            ),
            reloadRequired: true,
            actualAttachedRuleListIdentifiers: ["old.identifier"]
        )

        XCTAssertEqual(diagnostics.protectionLevel, .adblock)
        XCTAssertEqual(diagnostics.effectiveProtectionLevel, .adblock)
        XCTAssertEqual(diagnostics.generationSource, .embeddedBundle)
        XCTAssertEqual(diagnostics.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(diagnostics.activeGroups, plan.activeGroups)
        XCTAssertEqual(diagnostics.missingRuleListIdentifiers, plan.expectedRuleListIdentifiers)
        XCTAssertEqual(diagnostics.unexpectedOldRuleListIdentifiers, ["old.identifier"])
        XCTAssertTrue(diagnostics.reloadRequired)
        XCTAssertTrue(diagnostics.developerReport.contains("protectionLevel=adblock"))
        XCTAssertTrue(diagnostics.developerReport.contains("dedupeSummary="))
        XCTAssertTrue(diagnostics.developerReport.contains("overlapSummary="))
    }

    func testUnifiedSourceKeepsNativeModesScriptFreeAndEnhancedRuntimeSeparate() throws {
        let coordinatorSource = try Self.source(named: "Sumi/ContentBlocking/SumiProtectionCoordinator.swift")
        let tabRuntimeSource = try Self.source(named: "Sumi/Models/Tab/Tab+WebViewRuntime.swift")
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        XCTAssertFalse(coordinatorSource.contains("WKUserScript"))
        XCTAssertFalse(coordinatorSource.contains("WKWebExtension"))
        XCTAssertFalse(coordinatorSource.contains("MutationObserver"))
        XCTAssertFalse(coordinatorSource.contains("runtimeGenerated"))
        XCTAssertFalse(coordinatorSource.contains("compileNativeContentBlocking"))
        XCTAssertTrue(tabRuntimeSource.contains("protectionCoordinator"))
        XCTAssertTrue(tabRuntimeSource.contains(".normalTabDecision(for: url, profileId: profile.id)"))
        XCTAssertFalse(tabRuntimeSource.contains("additionalContentBlockingServices: [adBlockingDecision"))
        XCTAssertTrue(tabRuntimeSource.contains("normalTabEnhancedRuntimeScripts"))
        XCTAssertTrue(settingsSource.contains("DEBUG Legacy Protection Controls"))
        XCTAssertTrue(settingsSource.contains("Adblock & Protection"))
        XCTAssertTrue(settingsSource.contains("#if DEBUG"))
    }

    private struct CoordinatorFixture {
        let coordinator: SumiProtectionCoordinator
        let trackingRuleSource: RecordingTrackingRuleSource
        let adBlockingModule: SumiAdBlockingModule
        let didCreateAdblockRuleListStore: () -> Bool
    }

    private func makeCoordinatorFixture(
        defaults: UserDefaults,
        trackingDefinitions: [SumiContentRuleListDefinition]
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
            ruleListStoreFactory: { settings, isEnabled in
                didCreateAdblockRuleListStore = true
                return AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
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
