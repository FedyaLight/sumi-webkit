import XCTest

@testable import Sumi

@MainActor
final class SumiAdBlockingModuleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testCleanInstallDefaultsDisabledAndDoesNotLoadRuntime() {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults))
        let module = SumiAdBlockingModule(moduleRegistry: registry)

        XCTAssertFalse(module.isEnabled)
        XCTAssertEqual(module.status, .disabled)
        XCTAssertFalse(module.hasLoadedRuntime)
    }

    func testPreparedManifestExposesNativeNetworkDefinitionsWithoutScripts() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults))
        registry.enable(.adBlocking)
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: temporaryDirectory())
        _ = try await PreparedAdblockTestSupport.seedPreparedManifest(in: manifestStore)
        let module = makeModule(registry: registry, defaults: harness.defaults, manifestStore: manifestStore)

        _ = try await module.restorePreparedNativeRuleBundleForStartup(profileId: "adguardAdsPrivacy")
        let definitions = try module.contentRuleListDefinitions(for: [.network])
        let state = module.desiredAttachmentState(for: URL(string: "https://example.com")!)

        XCTAssertEqual(definitions.count, 2)
        XCTAssertTrue(definitions.contains { $0.name.hasPrefix("sumi.tracking.network.") })
        XCTAssertTrue(definitions.contains { $0.name.hasPrefix("sumi.adblock.network.") })
        XCTAssertTrue(state.isEnabled)
        XCTAssertEqual(state.attachedShardIdentifiers.count, 2)
    }

    func testPreparedDevelopmentBundleInstallPathStillWorks() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults))
        registry.enable(.adBlocking)
        let developmentRoot = temporaryDirectory()
        let bundleURL = developmentRoot
            .appendingPathComponent("adguardAdsPrivacy", isDirectory: true)
            .appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(at: bundleURL)
        let module = SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { AdblockSettingsStore(userDefaults: harness.defaults) },
            sitePolicyFactory: { AdblockSitePolicyStore(userDefaults: harness.defaults) },
            preparedBundleResourceURL: temporaryDirectory(),
            preparedBundleRemoteRootURL: temporaryDirectory(),
            preparedBundleGeneratedRootURL: developmentRoot,
            ruleListStoreFactory: { settings, isEnabled in
                AdblockWebKitRuleListStore(
                    settingsStore: settings,
                    isAdblockEnabled: isEnabled,
                    manifestStore: AdblockUpdateManifestStore(rootDirectory: self.temporaryDirectory()),
                    compiler: SumiWKContentRuleListCompiler(),
                    embeddedBundleURLProvider: { nil }
                )
            }
        )

        let manifest = try await module.installPreparedNativeRuleBundle(profileId: "adguardAdsPrivacy")

        XCTAssertEqual(manifest?.generationSource, .developmentBundle)
        XCTAssertEqual(manifest?.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(module.activeManifestIfLoaded()?.bundleProfileId, "adguardAdsPrivacy")
    }

    func testSiteOverrideDisablesPreparedAdblockWithoutTouchingGlobalState() async throws {
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults))
        registry.enable(.adBlocking)
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: temporaryDirectory())
        _ = try await PreparedAdblockTestSupport.seedPreparedManifest(in: manifestStore)
        let module = makeModule(registry: registry, defaults: harness.defaults, manifestStore: manifestStore)
        _ = try await module.restorePreparedNativeRuleBundleForStartup(profileId: "adguardAdsPrivacy")
        let url = URL(string: "https://example.com/page")!

        module.setSiteOverride(.disabled, for: url)

        XCTAssertEqual(module.siteOverride(for: url), .disabled)
        XCTAssertFalse(module.effectivePolicy(for: url).isEnabled)
        XCTAssertFalse(module.desiredAttachmentState(for: url).isEnabled)
        XCTAssertTrue(module.isEnabled)
    }

    func testAppRuntimeHasNoGenerationFallbackRustInvocationOrEnhancedRuntime() throws {
        let runtimeSources = try Self.combinedSource(in: "Sumi")
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        XCTAssertFalse(runtimeSources.contains("runtimeGenerated"))
        XCTAssertFalse(runtimeSources.contains("AdblockRustCompiler"))
        XCTAssertFalse(runtimeSources.contains("sumi-adblock-rust-adapter"))
        XCTAssertFalse(runtimeSources.contains("SumiAdblockEnhancedRuntime"))
        XCTAssertFalse(runtimeSources.contains("normalTabEnhancedRuntimeScripts"))
        XCTAssertFalse(settingsSource.localizedCaseInsensitiveContains("rebuild selected adblock profile now"))
        XCTAssertFalse(settingsSource.localizedCaseInsensitiveContains("raw list"))
    }

    private func makeModule(
        registry: SumiModuleRegistry,
        defaults: UserDefaults,
        manifestStore: AdblockUpdateManifestStore
    ) -> SumiAdBlockingModule {
        SumiAdBlockingModule(
            moduleRegistry: registry,
            settingsFactory: { AdblockSettingsStore(userDefaults: defaults) },
            sitePolicyFactory: { AdblockSitePolicyStore(userDefaults: defaults) },
            preparedBundleRemoteRootURL: temporaryDirectory(),
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
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiAdBlockingModuleTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private static func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(contentsOf: repoRoot.appendingPathComponent(relativePath), encoding: .utf8)
    }

    private static func combinedSource(in relativeDirectory: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let directory = repoRoot.appendingPathComponent(relativeDirectory)
        let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil)
        let urls = (enumerator?.allObjects as? [URL] ?? [])
            .filter { $0.pathExtension == "swift" }
        return try urls
            .map { try String(contentsOf: $0, encoding: .utf8) }
            .joined(separator: "\n")
    }
}
