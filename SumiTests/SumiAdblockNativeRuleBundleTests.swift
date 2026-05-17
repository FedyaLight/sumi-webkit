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

    func testPreparedBundleLoadVerifiesHashesAndRejectsTampering() throws {
        let bundleURL = temporaryDirectory().appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(at: bundleURL)
        let bundle = try SumiAdblockNativeRuleBundle.load(directoryURL: bundleURL)

        XCTAssertEqual(bundle.manifest.profileId, "adguardAdsPrivacy")
        XCTAssertEqual(try bundle.contentRuleListDefinitions().count, 1)

        let shardURL = bundleURL.appendingPathComponent("network/network-0001.json")
        var tampered = try Data(contentsOf: shardURL)
        tampered[tampered.startIndex] = tampered[tampered.startIndex] == 0x5B ? 0x7B : 0x5B
        try tampered.write(to: shardURL)

        XCTAssertThrowsError(try bundle.contentRuleListDefinitions()) { error in
            XCTAssertTrue(error.localizedDescription.contains("hash mismatch") || error.localizedDescription.contains("size mismatch"))
        }
    }

    func testPreparedBundleInstallPublishesDevelopmentBundleWithoutGeneration() async throws {
        let bundleURL = temporaryDirectory().appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(at: bundleURL)
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: temporaryDirectory())
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = AdblockWebKitRuleListStore(
            settingsStore: AdblockSettingsStore(userDefaults: harness.defaults),
            isAdblockEnabled: { true },
            manifestStore: manifestStore,
            compiler: SumiWKContentRuleListCompiler(),
            embeddedBundleURLProvider: { nil }
        )

        let installed = try await store.requestPreparedBundleInstall(
            bundleURL: bundleURL,
            source: .developmentBundle,
            profileId: "adguardAdsPrivacy"
        )
        let manifest = try XCTUnwrap(installed)

        XCTAssertEqual(manifest.generationSource, .developmentBundle)
        XCTAssertEqual(manifest.bundleProfileId, "adguardAdsPrivacy")
        XCTAssertEqual(manifest.nativeRuleBundleId, "sumi.adblock.bundle.adguardAdsPrivacy.test")
        XCTAssertEqual(manifest.networkShards.count, 1)
        XCTAssertEqual(manifest.nativeCSSShards.count, 0)
        XCTAssertEqual(store.lastUpdateDiagnostics?.summary, "success: Adblock bundle installed")
    }

    func testDevelopmentBundleCatalogStillFindsPreparedAdguardAdsPrivacyImport() throws {
        let resourceRoot = temporaryDirectory()
        let generatedRoot = temporaryDirectory()
        let developmentBundle = generatedRoot
            .appendingPathComponent("adguardAdsPrivacy", isDirectory: true)
            .appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(at: developmentBundle)

        let snapshot = SumiEmbeddedAdblockBundleCatalog.snapshot(
            resourceURL: resourceRoot,
            generatedBundlesRootURL: generatedRoot
        )

        XCTAssertEqual(snapshot.installableProfiles.map(\.profileId), ["adguardAdsPrivacy"])
        XCTAssertEqual(snapshot.installableProfiles.map(\.source), [.developmentBundle])
        XCTAssertTrue(snapshot.expectedDevelopmentPath.contains(".build/sumi-adblock-bundles/<profile>/SumiAdblockBundle") || snapshot.expectedDevelopmentPath.contains("<profile>/SumiAdblockBundle"))
    }

    func testPreparedBundleInstallRejectsUnsupportedNativeCSSSafetyPolicy() async throws {
        let bundleURL = temporaryDirectory().appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(
            at: bundleURL,
            nativeCSSSafetyPolicyVersion: "sumi-native-css-safety/0.3"
        )
        let harness = TestDefaultsHarness()
        defer { harness.reset() }
        let store = AdblockWebKitRuleListStore(
            settingsStore: AdblockSettingsStore(userDefaults: harness.defaults),
            isAdblockEnabled: { true },
            manifestStore: AdblockUpdateManifestStore(rootDirectory: temporaryDirectory()),
            compiler: SumiWKContentRuleListCompiler(),
            embeddedBundleURLProvider: { nil }
        )

        do {
            _ = try await store.requestPreparedBundleInstall(
                bundleURL: bundleURL,
                source: .developmentBundle,
                profileId: "adguardAdsPrivacy"
            )
            XCTFail("Expected safety-policy rejection")
        } catch let diagnostics as AdblockUpdateDiagnostics {
            XCTAssertEqual(diagnostics.stage, .embeddedBundleManifestRead)
            XCTAssertTrue(diagnostics.summary.contains("native CSS safety policy"))
        }
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiAdblockNativeRuleBundleTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }
}
