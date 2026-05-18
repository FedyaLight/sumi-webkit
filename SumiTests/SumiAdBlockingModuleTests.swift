import WebKit
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
#if DEBUG
        SumiProtectionStartupRestoreDiagnostics.shared.resetForTests()
#endif
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

    func testRepeatedPreparedManifestStartupRestoreUsesLookupOnlyWithoutShardPayloadReads() async throws {
#if DEBUG
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let registry = SumiModuleRegistry(settingsStore: SumiModuleSettingsStore(userDefaults: harness.defaults))
        registry.enable(.adBlocking)
        let root = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let generationId = "repeated-launch-\(UUID().uuidString)"
        let compiler = RetainingContentRuleListCompiler()
        let bundleURL = temporaryDirectory()
            .appendingPathComponent("adguardAdsPrivacy", isDirectory: true)
            .appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(at: bundleURL, generationId: generationId)
        let setupStore = AdblockWebKitRuleListStore(
            settingsStore: AdblockSettingsStore(userDefaults: harness.defaults),
            isAdblockEnabled: { true },
            manifestStore: manifestStore,
            compiler: compiler,
            embeddedBundleURLProvider: { nil }
        )
        let installed = try await setupStore.requestPreparedBundleInstall(
            bundleURL: bundleURL,
            source: .developmentBundle,
            profileId: "adguardAdsPrivacy"
        )
        let manifest = try XCTUnwrap(installed)

        SumiProtectionStartupRestoreDiagnostics.shared.resetForTests()
        let token = SumiProtectionStartupRestoreDiagnostics.shared.begin(
            appliedLevel: .adblock,
            trackedGenerationId: generationId
        )
        let warmStore = AdblockWebKitRuleListStore(
            settingsStore: AdblockSettingsStore(userDefaults: harness.defaults),
            isAdblockEnabled: { true },
            manifestStore: manifestStore,
            compiler: compiler,
            embeddedBundleURLProvider: { nil }
        )
        let restored = try await warmStore.restorePreparedManifestIfAvailable(profileId: "adguardAdsPrivacy")
        try await Task.sleep(nanoseconds: 250_000_000)
        let snapshot = SumiProtectionStartupRestoreDiagnostics.shared.finish(token)

        XCTAssertEqual(restored?.activeGenerationId, manifest.activeGenerationId)
        XCTAssertEqual(snapshot.activeGenerationId, manifest.activeGenerationId)
        XCTAssertEqual(snapshot.expectedShardIdentifiers, manifest.webKitRuleListIdentifiers)
        XCTAssertTrue(snapshot.wkContentRuleListStoreLookupAttempted)
        XCTAssertEqual(snapshot.lookupMissCount, 0)
        XCTAssertGreaterThanOrEqual(snapshot.lookupHitCount, manifest.webKitRuleListIdentifiers.count)
        XCTAssertTrue(snapshot.metadataOnlyRestoreUsed)
        XCTAssertFalse(snapshot.payloadBackedRestoreUsed)
        XCTAssertFalse(snapshot.repairCompileUsed)
        XCTAssertEqual(snapshot.totalShardJSONBytesRead, 0)
        XCTAssertEqual(snapshot.shardJSONFileReadCount, 0)
#else
        throw XCTSkip("Startup restore diagnostics are DEBUG-only.")
#endif
    }

    func testMissingCompiledRuleListFallsBackToPayloadRepairWithDiagnostics() async throws {
#if DEBUG
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: temporaryDirectory())
        let generationId = "missing-compiled-\(UUID().uuidString)"
        let manifest = try await PreparedAdblockTestSupport.seedPreparedManifest(
            in: manifestStore,
            generationId: generationId
        )
        let store = AdblockWebKitRuleListStore(
            settingsStore: AdblockSettingsStore(userDefaults: harness.defaults),
            isAdblockEnabled: { true },
            manifestStore: manifestStore,
            compiler: SumiWKContentRuleListCompiler(),
            embeddedBundleURLProvider: { nil }
        )

        let token = SumiProtectionStartupRestoreDiagnostics.shared.begin(
            appliedLevel: .adblock,
            trackedGenerationId: generationId
        )
        let restored = try await store.restorePreparedManifestIfAvailable(profileId: "adguardAdsPrivacy")
        let snapshot = SumiProtectionStartupRestoreDiagnostics.shared.finish(token)

        XCTAssertEqual(restored?.activeGenerationId, manifest.activeGenerationId)
        XCTAssertTrue(snapshot.wkContentRuleListStoreLookupAttempted)
        XCTAssertGreaterThan(snapshot.lookupMissCount, 0)
        XCTAssertTrue(snapshot.payloadBackedRestoreUsed)
        XCTAssertTrue(snapshot.repairCompileUsed)
        XCTAssertGreaterThan(snapshot.totalShardJSONBytesRead, 0)
        XCTAssertGreaterThan(snapshot.shardJSONFileReadCount, 0)
        XCTAssertTrue(snapshot.fallbackReason?.contains("lookup-only restore failed") == true)
#else
        throw XCTSkip("Startup restore diagnostics are DEBUG-only.")
#endif
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
        let runtimeSources = try [
            Self.combinedSource(in: "Sumi/ContentBlocking"),
            Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift"),
            Self.source(named: "Sumi/Models/Tab/Tab+WebViewRuntime.swift"),
        ].joined(separator: "\n")
        let settingsSource = try Self.source(named: "Sumi/Components/Settings/PrivacySettingsView.swift")

        XCTAssertFalse(runtimeSources.contains(Self.joined("runtime", "Generated")))
        XCTAssertFalse(runtimeSources.contains(Self.joined("Adblock", "Rust", "Compiler")))
        XCTAssertFalse(runtimeSources.contains(Self.joined("sumi", "-adblock", "-rust", "-adapter")))
        XCTAssertFalse(runtimeSources.contains(Self.joined("Sumi", "Adblock", "Enhanced", "Runtime")))
        XCTAssertFalse(runtimeSources.contains(Self.joined("normalTab", "Enhanced", "RuntimeScripts")))
        XCTAssertFalse(runtimeSources.contains("WKWebExtension"))
        XCTAssertFalse(runtimeSources.contains("WKUserScript(source:"))
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

    private static func joined(_ parts: String...) -> String {
        parts.joined()
    }
}

@MainActor
private final class RetainingContentRuleListCompiler: SumiContentRuleListCompiling {
    private let wrapped = SumiWKContentRuleListCompiler()
    private let backingIdentifierPrefix = "sumi.tests.retained.\(UUID().uuidString)"
    private var compiledRuleLists: [String: WKContentRuleList] = [:]
    private var compileSequence = 0

    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        compiledRuleLists[identifier]
    }

    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool {
        compiledRuleLists[identifier] != nil
    }

    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        compileSequence += 1
        let backingIdentifier = "\(backingIdentifierPrefix).\(compileSequence)"
        let ruleList = try await wrapped.compileContentRuleList(
            forIdentifier: backingIdentifier,
            encodedContentRuleList: encodedContentRuleList
        )
        compiledRuleLists[identifier] = ruleList
        return ruleList
    }

    func availableContentRuleListIdentifiers() async -> [String] {
        compiledRuleLists.keys.sorted()
    }

    func removeContentRuleList(forIdentifier identifier: String) async throws {
        compiledRuleLists.removeValue(forKey: identifier)
    }
}
