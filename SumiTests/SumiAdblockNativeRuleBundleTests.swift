import CryptoKit
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SumiAdblockNativeRuleBundleTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testBundleLoadVerifiesShardHashesAndRejectsTampering() throws {
        let bundleURL = try makeBundle()
        let bundle = try SumiAdblockNativeRuleBundle.load(directoryURL: bundleURL)

        XCTAssertEqual(bundle.manifest.schemaVersion, 1)
        XCTAssertEqual(bundle.manifest.profileId, "currentDefault")
        XCTAssertEqual(try bundle.contentRuleListDefinitions().count, 1)

        let shardURL = bundleURL.appendingPathComponent("network/network-0001.json")
        let tamperedJSON = Self.validNetworkRuleJSON().replacingOccurrences(of: "ads", with: "bad")
        XCTAssertEqual(Data(tamperedJSON.utf8).count, try Data(contentsOf: shardURL).count)
        try Data(tamperedJSON.utf8).write(to: shardURL)

        XCTAssertThrowsError(try bundle.contentRuleListDefinitions()) { error in
            XCTAssertTrue(error.localizedDescription.contains("hash mismatch"))
        }
    }

    func testEmbeddedBundleInstallCompilesWebKitShardsWithoutRustConversion() async throws {
        let bundleURL = try makeBundle()
        let adblockRoot = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: adblockRoot)
        let rustCompiler = RecordingNativeCompiler()
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let settings = AdblockSettingsStore(userDefaults: harness.defaults)
        let store = AdblockWebKitRuleListStore(
            settingsStore: settings,
            isAdblockEnabled: { true },
            manifestStore: manifestStore,
            nativeCompiler: rustCompiler,
            enhancedCompiler: rustCompiler,
            compiler: SumiWKContentRuleListCompiler(),
            embeddedBundleURLProvider: { bundleURL }
        )

        await store.loadActiveManifestIfEnabled()

        let active = try XCTUnwrap(store.activeManifest)
        let compileCount = await rustCompiler.compileCount()
        XCTAssertEqual(active.generationSource, .embeddedBundle)
        XCTAssertEqual(active.nativeRuleBundleId, "sumi.adblock.bundle.currentDefault.test")
        XCTAssertEqual(active.networkShards.count, 1)
        XCTAssertEqual(active.nativeCSSShards.count, 0)
        XCTAssertEqual(store.lastUpdateDiagnostics?.generationSource, .embeddedBundle)
        XCTAssertEqual(compileCount, 0)
    }

    func testExplicitEmbeddedBundleInstallSetsEmbeddedGenerationSource() async throws {
        let bundleURL = try makeBundle(profileId: "currentDefault")
        let adblockRoot = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: adblockRoot)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = AdblockWebKitRuleListStore(
            settingsStore: AdblockSettingsStore(userDefaults: harness.defaults),
            isAdblockEnabled: { true },
            manifestStore: manifestStore,
            compiler: SumiWKContentRuleListCompiler(),
            embeddedBundleURLProvider: { nil }
        )

        let installed = try await store.requestEmbeddedBundleInstall(bundleURL: bundleURL)

        let manifest = try XCTUnwrap(installed)
        XCTAssertEqual(manifest.generationSource, .embeddedBundle)
        XCTAssertEqual(manifest.nativeRuleBundleId, "sumi.adblock.bundle.currentDefault.test")
        XCTAssertEqual(manifest.nativeProfile, .currentDefault)
        XCTAssertEqual(store.activeManifest?.generationSource, .embeddedBundle)
        XCTAssertEqual(store.lastUpdateDiagnostics?.summary, "success: Adblock bundle installed")
        XCTAssertEqual(store.lastUpdateDiagnostics?.bundleProfileId, "currentDefault")
        XCTAssertEqual(store.lastUpdateDiagnostics?.nativeRuleBundleId, "sumi.adblock.bundle.currentDefault.test")
    }

    func testEmbeddedBundleCatalogListsResourceProfiles() throws {
        let sourceBundleURL = try makeBundle(profileId: "currentDefault")
        let resourceRoot = temporaryDirectory()
        let embeddedRoot = resourceRoot
            .appendingPathComponent("SumiAdblockBundles/currentDefault", isDirectory: true)
        try FileManager.default.createDirectory(at: embeddedRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: sourceBundleURL,
            to: embeddedRoot.appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        )

        let snapshot = SumiEmbeddedAdblockBundleCatalog.snapshot(
            resourceURL: resourceRoot,
            generatedBundlesRootURL: temporaryDirectory()
        )

        XCTAssertEqual(snapshot.installableProfiles.map(\.profileId), ["currentDefault"])
        XCTAssertEqual(snapshot.installableProfiles.map(\.source), [.appResource])
        XCTAssertEqual(snapshot.installableProfiles.first?.bundleId, "sumi.adblock.bundle.currentDefault.test")
        XCTAssertEqual(snapshot.installableProfiles.first?.networkShardCount, 1)
        XCTAssertEqual(snapshot.installableProfiles.first?.networkRuleCount, 1)
        XCTAssertFalse(snapshot.generatedBundlesPresentOutsideAppResources)
    }

    func testEmbeddedBundleCatalogListsDevelopmentProfilesWithoutAppCopy() throws {
        let sourceBundleURL = try makeBundle(profileId: "adguardAdsOnly")
        let resourceRoot = temporaryDirectory()
        let generatedRoot = temporaryDirectory()
        let developmentRoot = generatedRoot
            .appendingPathComponent("adguardAdsOnly", isDirectory: true)
        try FileManager.default.createDirectory(at: developmentRoot, withIntermediateDirectories: true)
        try FileManager.default.copyItem(
            at: sourceBundleURL,
            to: developmentRoot.appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        )

        let snapshot = SumiEmbeddedAdblockBundleCatalog.snapshot(
            resourceURL: resourceRoot,
            generatedBundlesRootURL: generatedRoot
        )

        XCTAssertEqual(snapshot.installableProfiles.map(\.profileId), ["adguardAdsOnly"])
        XCTAssertEqual(snapshot.installableProfiles.map(\.source), [.developmentBundle])
        XCTAssertTrue(snapshot.expectedDevelopmentPath.contains(".build/sumi-adblock-bundles/<profile>/SumiAdblockBundle") || snapshot.expectedDevelopmentPath.contains("<profile>/SumiAdblockBundle"))
        XCTAssertTrue(snapshot.generatedBundlesPresentOutsideAppResources)
    }

    func testDevelopmentBundleInstallSetsDevelopmentGenerationSource() async throws {
        let bundleURL = try makeBundle(profileId: "adguardAdsOnly")
        let adblockRoot = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: adblockRoot)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = AdblockWebKitRuleListStore(
            settingsStore: AdblockSettingsStore(userDefaults: harness.defaults),
            isAdblockEnabled: { true },
            manifestStore: manifestStore,
            compiler: SumiWKContentRuleListCompiler(),
            embeddedBundleURLProvider: { nil }
        )

        let installed = try await store.requestEmbeddedBundleInstall(
            bundleURL: bundleURL,
            source: .developmentBundle,
            profileId: "adguardAdsOnly"
        )

        let manifest = try XCTUnwrap(installed)
        XCTAssertEqual(manifest.generationSource, .developmentBundle)
        XCTAssertEqual(manifest.nativeRuleBundleId, "sumi.adblock.bundle.adguardAdsOnly.test")
        XCTAssertNil(manifest.nativeProfile)
        XCTAssertEqual(manifest.bundleProfileId, "adguardAdsOnly")
        XCTAssertEqual(store.activeManifest?.generationSource, .developmentBundle)
        XCTAssertEqual(store.lastUpdateDiagnostics?.generationSource, .developmentBundle)
        XCTAssertEqual(store.lastUpdateDiagnostics?.bundleProfileId, "adguardAdsOnly")
    }

    func testMissingEmbeddedBundleCatalogReportsClearDiagnosticsAndGeneratedPresence() throws {
        let resourceRoot = temporaryDirectory()
        let generatedRoot = temporaryDirectory()
        let generatedManifest = generatedRoot
            .appendingPathComponent("currentDefault/SumiAdblockBundle/manifest.json")
        try FileManager.default.createDirectory(
            at: generatedManifest.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("{}".utf8).write(to: generatedManifest)

        let snapshot = SumiEmbeddedAdblockBundleCatalog.snapshot(
            resourceURL: resourceRoot,
            generatedBundlesRootURL: generatedRoot
        )

        XCTAssertFalse(snapshot.installableProfiles.contains { $0.isInstallable })
        XCTAssertTrue(snapshot.expectedResourcePath.contains("SumiAdblockBundles/<profile>/SumiAdblockBundle"))
        XCTAssertTrue(snapshot.expectedDevelopmentPath.contains("<profile>/SumiAdblockBundle"))
        XCTAssertTrue(snapshot.generateCommand.contains("scripts/build_sumi_adblock_bundle.sh"))
        XCTAssertEqual(snapshot.generatedBundlesRootPath, generatedRoot.path)
        XCTAssertTrue(snapshot.generatedBundlesPresentOutsideAppResources)
    }

    func testBundleInstallRejectsOlderNativeCSSSafetyPolicyWithStage() async throws {
        let bundleURL = try makeBundle(nativeCSSSafetyPolicyVersion: "sumi-native-css-safety/0.3")
        let adblockRoot = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: adblockRoot)
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = AdblockWebKitRuleListStore(
            settingsStore: AdblockSettingsStore(userDefaults: harness.defaults),
            isAdblockEnabled: { true },
            manifestStore: manifestStore,
            compiler: SumiWKContentRuleListCompiler(),
            embeddedBundleURLProvider: { nil }
        )

        do {
            _ = try await store.requestEmbeddedBundleInstall(bundleURL: bundleURL)
            XCTFail("Expected safety policy rejection")
        } catch let diagnostics as AdblockUpdateDiagnostics {
            XCTAssertEqual(diagnostics.stage, .embeddedBundleManifestRead)
            XCTAssertEqual(diagnostics.bundleProfileId, nil)
            XCTAssertTrue(diagnostics.summary.contains("native CSS safety policy"))
        }
    }

    func testEmbeddedBundleInstallPreservesPreviousGenerationForRollback() async throws {
        let bundleURL = try makeBundle(generationId: "embedded-generation")
        let adblockRoot = temporaryDirectory()
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: adblockRoot)
        try await seedActiveRuntimeGeneration(in: manifestStore, generationId: "runtime-generation")
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = AdblockWebKitRuleListStore(
            settingsStore: AdblockSettingsStore(userDefaults: harness.defaults),
            isAdblockEnabled: { true },
            manifestStore: manifestStore,
            compiler: SumiWKContentRuleListCompiler(),
            embeddedBundleURLProvider: { bundleURL }
        )

        await store.loadActiveManifestIfEnabled()

        let optionalActive = try await manifestStore.activeManifest()
        let active = try XCTUnwrap(optionalActive)
        let previous = try await manifestStore.archivedManifest(generationId: "runtime-generation")
        XCTAssertEqual(active.activeGenerationId, "embedded-generation")
        XCTAssertEqual(active.previousGenerationId, "runtime-generation")
        XCTAssertEqual(active.generationSource, .embeddedBundle)
        XCTAssertNotNil(previous)
    }

    private func makeBundle(
        generationId: String = "embedded-generation",
        profileId: String = "currentDefault",
        nativeCSSSafetyPolicyVersion: String = "sumi-native-css-safety/0.4"
    ) throws -> URL {
        let root = temporaryDirectory()
        let bundleURL = root.appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        let networkURL = bundleURL.appendingPathComponent("network", isDirectory: true)
        try FileManager.default.createDirectory(at: networkURL, withIntermediateDirectories: true)
        let shardJSON = Self.validNetworkRuleJSON()
        let shardData = Data(shardJSON.utf8)
        let shardHash = Self.sha256Hex(shardData)
        try shardData.write(to: networkURL.appendingPathComponent("network-0001.json"))

        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "bundleId": "sumi.adblock.bundle.\(profileId).test",
            "generationId": generationId,
            "profileId": profileId,
            "compiler": [
                "name": "adblock-rust",
                "version": "adblock-rust-adapter/0.1.0 adblock-rust/0.12.5 \(nativeCSSSafetyPolicyVersion)",
            ],
            "nativeCSSSafetyPolicyVersion": nativeCSSSafetyPolicyVersion,
            "generatedDate": "2026-05-17T00:00:00Z",
            "lists": [
                [
                    "id": "easylist",
                    "displayName": "EasyList",
                    "url": "https://easylist.to/easylist/easylist.txt",
                    "hash": "easylist-hash",
                    "byteSize": 24,
                    "ruleCount": 1,
                    "category": "baseAds",
                ],
            ],
            "shards": [
                [
                    "kind": "network",
                    "group": "network",
                    "relativePath": "network/network-0001.json",
                    "hash": shardHash,
                    "byteSize": shardData.count,
                    "ruleCount": 1,
                    "webKitIdentifier": "sumi.adblock.network.\(generationId).0001.\(shardHash.prefix(12))",
                ],
            ],
            "diagnosticsSummary": [
                "inputRuleCount": 1,
                "finalRuleCount": 1,
                "finalShardCount": 1,
                "networkRuleCount": 1,
                "nativeCSSRuleCount": 0,
                "unsafeCSSFilteredCount": 0,
                "warnings": [],
            ],
            "unsafeCSSFilteredCount": 0,
            "deduplication": [
                "inputRawRuleCount": 1,
                "rawDuplicateCountRemoved": 0,
                "nativeJSONDuplicateCountRemoved": 0,
                "skippedDedupeCount": 0,
                "skippedDedupeReasons": [String: Int](),
                "finalRuleCount": 1,
                "finalShardCount": 1,
            ],
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        try manifestData.write(to: bundleURL.appendingPathComponent("manifest.json"))
        try Data("{}".utf8).write(to: bundleURL.appendingPathComponent("diagnostics.json"))
        return bundleURL
    }

    private func seedActiveRuntimeGeneration(
        in manifestStore: AdblockUpdateManifestStore,
        generationId: String
    ) async throws {
        let shardData = Data(Self.validNetworkRuleJSON().utf8)
        let shardHash = Self.sha256Hex(shardData)
        let shard = NativeContentBlockingShardDescriptor(
            id: "network-0001",
            generationId: generationId,
            kind: .network,
            sourceListIdentifiers: ["easylist"],
            sourceCategories: [.baseAds],
            webKitIdentifier: "sumi.adblock.network.\(generationId).0001.\(shardHash.prefix(12))",
            contentHash: shardHash,
            approximateRuleCount: 1,
            jsonByteCount: shardData.count,
            compilerIdentity: NativeContentBlockingCompilerIdentity(
                name: "adblock-rust",
                version: "test"
            ),
            profileIdentity: .currentDefault,
            diagnosticsSummary: "test"
        )
        let manifest = AdblockCompiledGenerationManifest(
            schemaVersion: 6,
            activeGenerationId: generationId,
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            selectedFilterLists: [
                AdblockCompiledGenerationManifest.SelectedFilterList(
                    id: "easylist",
                    displayName: "EasyList",
                    contentHash: "easylist-hash"
                ),
            ],
            networkShards: [shard],
            nativeCSSShards: [],
            enhancedRuntimeBundle: nil,
            nativeProfile: .currentDefault,
            nativeCompiler: shard.compilerIdentity,
            nativeCompilerSourceLists: nil,
            compilerDiagnosticsSummary: "generationSource=runtimeGenerated",
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 1_700_000_000),
            previousGenerationId: nil,
            generationSource: .runtimeGenerated
        )
        let stagingDirectory = try await manifestStore.beginStaging()
        let stagedShardURL = stagingDirectory.appendingPathComponent("network-0001.json")
        try shardData.write(to: stagedShardURL)
        try await manifestStore.commit(
            manifest: manifest,
            httpMetadata: [:],
            stagedRawListURLs: [:],
            stagedCompiledShardURLs: ["network-0001": stagedShardURL]
        )
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiAdblockNativeRuleBundleTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private static func validNetworkRuleJSON() -> String {
        """
        [
          {
            "trigger": {
              "url-filter": ".*ads\\\\.example/.*"
            },
            "action": {
              "type": "block"
            }
          }
        ]
        """
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private actor RecordingNativeCompiler: NativeContentBlockingCompiler, EnhancedCompatibilityCompiler {
    nonisolated let identity = NativeContentBlockingCompilerIdentity(
        name: "recording-rust-boundary",
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
        throw AdblockUpdateDiagnostics(summary: "Native compiler should not run for embedded bundles")
    }

    func compileEnhancedCompatibility(
        _ input: AdblockCompilationInput
    ) async throws -> EnhancedCompatibilityCompilationOutput {
        calls += 1
        throw AdblockUpdateDiagnostics(summary: "Enhanced compiler should not run for embedded bundles")
    }
}
