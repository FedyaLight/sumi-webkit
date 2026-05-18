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

    func testOnlyFinalProductLevelsExistAndExtremeMigratesToAdblock() {
        XCTAssertEqual(SumiProtectionLevel.allCases, [.off, .protection, .adblock])
        XCTAssertEqual(SumiProtectionLevel.allCases.map(\.displayTitle), ["Off", "Protection", "Adblock"])

        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        harness.defaults.set("extreme", forKey: "settings.protection.level")
        harness.defaults.set("extreme", forKey: "settings.protection.appliedLevel")

        let settings = SumiProtectionSettings(userDefaults: harness.defaults)

        XCTAssertEqual(settings.level, .adblock)
        XCTAssertEqual(settings.appliedLevel, .adblock)
        XCTAssertEqual(harness.defaults.string(forKey: "settings.protection.level"), "adblock")
        XCTAssertEqual(harness.defaults.string(forKey: "settings.protection.appliedLevel"), "adblock")
    }

    func testFinalLevelMappingIsOffProtectionAdblockOnly() {
        XCTAssertEqual(SumiProtectionLevel.off.requestedGroups, [])
        XCTAssertEqual(SumiProtectionLevel.protection.requestedGroups, [.trackingNetwork])
        XCTAssertEqual(SumiProtectionLevel.adblock.requestedGroups, [.trackingNetwork, .adblockAdsPrivacyNetwork])
        XCTAssertNil(SumiProtectionLevel.off.preferredBundleProfileId)
        XCTAssertEqual(SumiProtectionLevel.protection.preferredBundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(SumiProtectionLevel.adblock.preferredBundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(SumiProtectionLevel.adblock.adblockRuleGroupKinds, [.network])
    }

    func testOffSkipsBundleDiscoveryInstallLookupAndRuleAttachment() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryDirectory(prefix: "SumiProtectionResource")
        let developmentRoot = temporaryDirectory(prefix: "SumiProtectionDevelopment")
        try makePreparedDevelopmentBundle(in: developmentRoot)
        let fixture = makeFixture(
            defaults: harness.defaults,
            resourceRoot: resourceRoot,
            developmentRoot: developmentRoot
        )

        fixture.coordinator.setLevel(.off)
        _ = try await fixture.coordinator.applySelectedLevel()
        _ = try await fixture.coordinator.restoreAppliedLevelForStartup()
        let decision = fixture.coordinator.normalTabDecision(for: URL(string: "https://example.com/off")!, profileId: nil)
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertEqual(decision.plan.effectiveLevel, .off)
        XCTAssertTrue(decision.plan.activeGroups.isEmpty)
        XCTAssertTrue(decision.plan.expectedRuleListIdentifiers.isEmpty)
        XCTAssertNil(decision.contentBlockingService)
        XCTAssertTrue(global.searchedBundlePaths.isEmpty)
        XCTAssertNil(global.bundleProfileId)
        XCTAssertFalse(fixture.didCreateAdblockRuleListStore())
    }

    func testManualBundleUpdateWhileOffCachesOnlyAndDoesNotLoadAdblockRuntime() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let updater = FakeProtectionBundleRemoteUpdater(
            result: SumiProtectionRemoteBundleFetchResult(
                profileId: SumiProtectionBundleProfile.adblock,
                releaseVersion: "20260517T000000Z-test",
                releaseTag: "bundles-20260517T000000Z-test",
                releaseURL: "https://example.test/release",
                publishedDate: nil,
                manifestSignatureRequired: true,
                manifestSignatureVerified: true,
                signingKeyId: "sumi-protection-bundles-ed25519-v1",
                signingKeyVersion: 1,
                bundleId: "sumi.adblock.bundle.adguardAdsPrivacy.test",
                generationId: "remote-generation",
                bundleURL: temporaryDirectory(prefix: "SumiProtectionRemoteResult")
            )
        )
        let fixture = makeFixture(
            defaults: harness.defaults,
            resourceRoot: temporaryDirectory(prefix: "SumiProtectionResource"),
            developmentRoot: temporaryDirectory(prefix: "SumiProtectionDevelopment"),
            bundleRemoteUpdater: updater,
            bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore(userDefaults: harness.defaults)
        )

        fixture.coordinator.setLevel(.off)
        let outcome = try await fixture.coordinator.updatePreparedBundlesManually()

        XCTAssertEqual(outcome.activation, .cachedOnly)
        XCTAssertFalse(fixture.didCreateAdblockRuleListStore())
        XCTAssertFalse(fixture.coordinator.globalDiagnostics().browserRestartRequired)
        XCTAssertEqual(fixture.coordinator.bundleUpdateStatusStore.lastReleaseVersion, "20260517T000000Z-test")
        XCTAssertEqual(fixture.coordinator.bundleUpdateStatusStore.lastSignatureVerified, true)
        XCTAssertEqual(fixture.coordinator.bundleUpdateStatusStore.lastSigningKeyId, "sumi-protection-bundles-ed25519-v1")
    }

    func testProtectionActivatesTrackingNetworkOnly() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryDirectory(prefix: "SumiProtectionResource")
        let developmentRoot = temporaryDirectory(prefix: "SumiProtectionDevelopment")
        try makePreparedDevelopmentBundle(in: developmentRoot)
        let fixture = makeFixture(
            defaults: harness.defaults,
            resourceRoot: resourceRoot,
            developmentRoot: developmentRoot
        )

        fixture.coordinator.setLevel(.protection)
        _ = try await fixture.coordinator.applySelectedLevel()
        XCTAssertTrue(fixture.coordinator.settings.browserRestartRequired)
        _ = try await fixture.coordinator.restoreAppliedLevelForStartup()
        let decision = fixture.coordinator.normalTabDecision(for: URL(string: "https://example.com")!, profileId: nil)
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertEqual(decision.plan.effectiveLevel, .protection)
        XCTAssertEqual(decision.plan.activeGroups, [.trackingNetwork])
        XCTAssertTrue(decision.plan.expectedRuleListIdentifiers.allSatisfy { $0.hasPrefix("sumi.tracking.network.") })
        XCTAssertTrue(decision.plan.trackingGroupActive)
        XCTAssertFalse(decision.plan.adblockGroupActive)
        XCTAssertTrue(global.groupSourceDiagnostics[.trackingNetwork]?.contains("sourceName=DuckDuckGo Tracker Radar / TDS") == true)
        XCTAssertTrue(global.groupSourceDiagnostics[.trackingNetwork]?.contains("sourceLicense=CC BY-NC-SA 4.0") == true)
        XCTAssertTrue(fixture.didCreateAdblockRuleListStore())
    }

    func testAdblockRequiresAndInstallsPreparedAdguardAdsPrivacyDevelopmentBundle() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryDirectory(prefix: "SumiProtectionResource")
        let developmentRoot = temporaryDirectory(prefix: "SumiProtectionDevelopment")
        try makePreparedDevelopmentBundle(in: developmentRoot)
        let fixture = makeFixture(
            defaults: harness.defaults,
            resourceRoot: resourceRoot,
            developmentRoot: developmentRoot
        )

        fixture.coordinator.setLevel(.adblock)
        let outcome = try await fixture.coordinator.applySelectedLevel()
        XCTAssertTrue(fixture.coordinator.settings.browserRestartRequired)
        _ = try await fixture.coordinator.restoreAppliedLevelForStartup()
        let plan = fixture.coordinator.rulePlan(for: URL(string: "https://example.com")!, profileId: nil)
        let global = fixture.coordinator.globalDiagnostics()

        XCTAssertEqual(outcome.installedBundleProfileId, "adguardAdsPrivacy")
        XCTAssertFalse(global.browserRestartRequired)
        XCTAssertEqual(plan.effectiveLevel, .adblock)
        XCTAssertEqual(plan.activeGroups, [.adblockAdsPrivacyNetwork, .trackingNetwork])
        XCTAssertEqual(plan.bundleSource, .developmentBundle)
        XCTAssertEqual(plan.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(plan.requiredBundleProfileId, "adguardAdsPrivacy")
        XCTAssertTrue(plan.expectedRuleListIdentifiers.contains { $0.hasPrefix("sumi.tracking.network.") })
        XCTAssertTrue(plan.expectedRuleListIdentifiers.contains { $0.hasPrefix("sumi.adblock.network.") })
        XCTAssertEqual(global.preparedBundleSource, .developmentBundle)
        XCTAssertTrue(fixture.didCreateAdblockRuleListStore())
    }

    func testMissingTrackingNetworkReportsClearError() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let resourceRoot = temporaryDirectory(prefix: "SumiProtectionResource")
        let developmentRoot = temporaryDirectory(prefix: "SumiProtectionDevelopment")
        try makePreparedDevelopmentBundle(in: developmentRoot, includeTrackingNetwork: false)
        let fixture = makeFixture(
            defaults: harness.defaults,
            resourceRoot: resourceRoot,
            developmentRoot: developmentRoot
        )

        fixture.coordinator.setLevel(.protection)
        do {
            _ = try await fixture.coordinator.applySelectedLevel()
            XCTFail("Expected missing prepared trackingNetwork error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("trackingNetwork"))
            XCTAssertTrue(error.localizedDescription.contains("prepared"))
        }
    }

    func testMissingAdguardAdsPrivacyReportsClearError() async {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let fixture = makeFixture(
            defaults: harness.defaults,
            resourceRoot: temporaryDirectory(prefix: "SumiProtectionResource"),
            developmentRoot: temporaryDirectory(prefix: "SumiProtectionDevelopment")
        )

        fixture.coordinator.setLevel(.adblock)
        do {
            _ = try await fixture.coordinator.applySelectedLevel()
            XCTFail("Expected missing prepared bundle error")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("adguardAdsPrivacy"))
            XCTAssertTrue(error.localizedDescription.contains("prepared bundle"))
        }
    }

    func testNativeProtectionModesRemainJSFreeAndNormalTabAttachmentStaysCoordinated() throws {
        let tabRuntimeSource = try Self.source(named: "Sumi/Models/Tab/Tab+WebViewRuntime.swift")
        let coordinatorSource = try Self.source(named: "Sumi/ContentBlocking/SumiProtectionCoordinator.swift")

        XCTAssertFalse(tabRuntimeSource.contains("normalTabEnhancedRuntimeScripts"))
        XCTAssertFalse(tabRuntimeSource.contains("MutationObserver"))
        XCTAssertFalse(tabRuntimeSource.contains("WKUserScript(source:"))
        XCTAssertTrue(tabRuntimeSource.contains(".normalTabDecision(for: url, profileId: profile.id)"))
        XCTAssertFalse(tabRuntimeSource.contains("adBlockingModule.normalTabDecision"))
        XCTAssertFalse(tabRuntimeSource.contains("trackingProtectionModule.normalTabDecision"))
        XCTAssertFalse(tabRuntimeSource.contains("SumiTrackingProtection"))
        XCTAssertFalse(coordinatorSource.contains("SumiTrackingProtectionModule"))
        XCTAssertFalse(coordinatorSource.contains("SumiTrackingProtectionTrackerDataSet"))
        XCTAssertTrue(coordinatorSource.contains("SumiProtectionCoordinator"))
    }

    private func makeFixture(
        defaults: UserDefaults,
        resourceRoot: URL? = nil,
        developmentRoot: URL? = nil,
        bundleRemoteUpdater: (any SumiProtectionBundleRemoteUpdating)? = nil,
        bundleUpdateStatusStore: SumiProtectionBundleUpdateStatusStore? = nil
    ) -> Fixture {
        let registry = SumiModuleRegistry(settingsStore: SumiModuleSettingsStore(userDefaults: defaults))
        var didCreateAdblockRuleListStore = false
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: temporaryDirectory(prefix: "SumiProtectionAdblock"))
        let adBlockingModule = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { AdblockSettingsStore(userDefaults: defaults) },
            sitePolicyFactory: { AdblockSitePolicyStore(userDefaults: defaults) },
            preparedBundleResourceURL: resourceRoot,
            preparedBundleRemoteRootURL: temporaryDirectory(prefix: "SumiProtectionRemote"),
            preparedBundleGeneratedRootURL: developmentRoot,
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
        let coordinator = SumiProtectionCoordinator(
            settings: SumiProtectionSettings(userDefaults: defaults),
            adBlockingModule: adBlockingModule,
            moduleRegistry: registry,
            bundleRemoteUpdater: bundleRemoteUpdater ?? FakeProtectionBundleRemoteUpdater(),
            bundleUpdateStatusStore: bundleUpdateStatusStore ?? SumiProtectionBundleUpdateStatusStore(userDefaults: defaults)
        )
        return Fixture(
            coordinator: coordinator,
            didCreateAdblockRuleListStore: { didCreateAdblockRuleListStore }
        )
    }

    private func makePreparedDevelopmentBundle(
        in root: URL,
        includeTrackingNetwork: Bool = true
    ) throws {
        let bundleURL = root
            .appendingPathComponent("adguardAdsPrivacy", isDirectory: true)
            .appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(
            at: bundleURL,
            includeTrackingNetwork: includeTrackingNetwork
        )
    }

    private func temporaryDirectory(prefix: String) -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(prefix)-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private struct Fixture {
        let coordinator: SumiProtectionCoordinator
        let didCreateAdblockRuleListStore: () -> Bool
    }
}

private final class FakeProtectionBundleRemoteUpdater: SumiProtectionBundleRemoteUpdating, @unchecked Sendable {
    var result: SumiProtectionRemoteBundleFetchResult?
    var error: Error?

    init(result: SumiProtectionRemoteBundleFetchResult? = nil, error: Error? = nil) {
        self.result = result
        self.error = error
    }

    func fetchLatestApprovedBundle(profileId: String) async throws -> SumiProtectionRemoteBundleFetchResult {
        if let error { throw error }
        return result ?? SumiProtectionRemoteBundleFetchResult(
            profileId: profileId,
            releaseVersion: "20260517T000000Z-test",
            releaseTag: "bundles-20260517T000000Z-test",
            releaseURL: nil,
            publishedDate: nil,
            manifestSignatureRequired: true,
            manifestSignatureVerified: true,
            signingKeyId: "sumi-protection-bundles-ed25519-v1",
            signingKeyVersion: 1,
            bundleId: "sumi.adblock.bundle.\(profileId).test",
            generationId: "remote-generation",
            bundleURL: URL(fileURLWithPath: "/tmp/SumiProtectionFakeRemoteBundle", isDirectory: true)
        )
    }
}
