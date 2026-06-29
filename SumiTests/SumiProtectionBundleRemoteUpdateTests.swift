import CryptoKit
import WebKit
import XCTest

@testable import Sumi

final class SumiProtectionBundleRemoteUpdateTests: XCTestCase {
    func testSignatureVerifierAcceptsValidEd25519Envelope() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let keyId = "test-key"
        let manifestData = Data(#"{"releaseVersion":"test"}"#.utf8)
        let signature = try privateKey.signature(for: manifestData)
        let envelope = try Self.signatureEnvelopeData(
            keyId: keyId,
            signedAsset: SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName,
            signature: signature
        )
        let verifier = SumiProtectionBundleSignatureVerifier(
            keys: [
                SumiProtectionBundleSigningKey(
                    id: keyId,
                    version: 7,
                    publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
                ),
            ]
        )

        let result = try verifier.verify(
            manifestData: manifestData,
            signatureData: envelope,
            expectedSignedAsset: SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName
        )

        XCTAssertEqual(result, SumiProtectionBundleSignatureVerification(keyId: keyId, keyVersion: 7))
    }

    func testSignatureVerifierRejectsEnvelopeForWrongAsset() throws {
        let privateKey = Curve25519.Signing.PrivateKey()
        let manifestData = Data("manifest".utf8)
        let envelope = try Self.signatureEnvelopeData(
            keyId: "test-key",
            signedAsset: "other.json",
            signature: privateKey.signature(for: manifestData)
        )
        let verifier = SumiProtectionBundleSignatureVerifier(
            keys: [
                SumiProtectionBundleSigningKey(
                    id: "test-key",
                    version: 1,
                    publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
                ),
            ]
        )

        XCTAssertThrowsError(
            try verifier.verify(
                manifestData: manifestData,
                signatureData: envelope,
                expectedSignedAsset: SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName
            )
        ) { error in
            XCTAssertEqual(
                error as? SumiProtectionBundleRemoteUpdateError,
                .signatureMetadataMalformed(
                    "signature covers other.json, expected \(SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName)"
                )
            )
        }
    }

    @MainActor
    func testBundleUpdateStatusStoreClassifiesTrustFailuresAndDowngrades() throws {
        let suiteName = "SumiProtectionBundleRemoteUpdateTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        let store = SumiProtectionBundleUpdateStatusStore(userDefaults: defaults)

        store.recordFailure(SumiProtectionBundleRemoteUpdateError.signatureInvalid("test-key"))

        XCTAssertEqual(store.lastFailureReason, SumiProtectionBundleRemoteUpdateError.signatureInvalid("test-key").localizedDescription)
        XCTAssertEqual(store.lastSignatureError, SumiProtectionBundleRemoteUpdateError.signatureInvalid("test-key").localizedDescription)
        XCTAssertFalse(try XCTUnwrap(store.lastSignatureVerified))
        XCTAssertFalse(try XCTUnwrap(store.lastDowngradeRejected))

        store.recordFailure(
            SumiProtectionBundleRemoteUpdateError.releaseDowngradeRejected(
                current: "20260626",
                incoming: "20260625"
            )
        )

        XCTAssertTrue(try XCTUnwrap(store.lastDowngradeRejected))
    }

    @MainActor
    func testBundleLifecycleRecordsSuccessAfterManualUpdateActivation() async throws {
        let suiteName = "SumiProtectionBundleLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        let statusStore = SumiProtectionBundleUpdateStatusStore(userDefaults: defaults)
        let profileId = SumiProtectionBundleProfile.adblock
        let manager = FakePreparedBundleManager(
            activeManifest: Self.makeCompiledManifest(
                bundleId: "old-bundle",
                generationId: "old-generation",
                profileId: profileId
            ),
            installManifest: Self.makeCompiledManifest(
                bundleId: "new-bundle",
                generationId: "new-generation",
                profileId: profileId
            )
        )
        let updater = FakeBundleRemoteUpdater(
            result: .success(
                Self.makeRemoteFetchResult(
                    profileId: profileId,
                    bundleId: "new-bundle",
                    generationId: "new-generation"
                )
            )
        )
        let lifecycle = SumiProtectionBundleLifecycle(
            preparedBundleManager: manager,
            remoteUpdater: updater,
            statusStore: statusStore
        )
        var activationCount = 0

        let outcome = try await lifecycle.updatePreparedBundlesManually(
            appliedLevel: .adblock,
            currentBrowserRestartRequired: false
        ) { _ in
            activationCount += 1
        }

        XCTAssertEqual(outcome.activation, .installedRestartRequired)
        XCTAssertTrue(outcome.browserRestartRequired)
        XCTAssertEqual(manager.installProfileIds, [profileId])
        XCTAssertEqual(activationCount, 1)
        XCTAssertEqual(statusStore.lastReleaseVersion, "20260626T120000Z")
        XCTAssertNil(statusStore.lastFailureReason)
    }

    @MainActor
    func testBundleLifecycleRecordsFailureWhenManualUpdateActivationFails() async throws {
        let suiteName = "SumiProtectionBundleLifecycleTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.removePersistentDomain(forName: suiteName)
        let statusStore = SumiProtectionBundleUpdateStatusStore(userDefaults: defaults)
        let profileId = SumiProtectionBundleProfile.adblock
        let manager = FakePreparedBundleManager(
            activeManifest: Self.makeCompiledManifest(
                bundleId: "old-bundle",
                generationId: "old-generation",
                profileId: profileId
            ),
            installManifest: Self.makeCompiledManifest(
                bundleId: "new-bundle",
                generationId: "new-generation",
                profileId: profileId
            )
        )
        let updater = FakeBundleRemoteUpdater(
            result: .success(
                Self.makeRemoteFetchResult(
                    profileId: profileId,
                    bundleId: "new-bundle",
                    generationId: "new-generation"
                )
            )
        )
        let lifecycle = SumiProtectionBundleLifecycle(
            preparedBundleManager: manager,
            remoteUpdater: updater,
            statusStore: statusStore
        )

        do {
            _ = try await lifecycle.updatePreparedBundlesManually(
                appliedLevel: .adblock,
                currentBrowserRestartRequired: false
            ) { _ in
                throw TestActivationError.failed
            }
            XCTFail("Expected activation failure")
        } catch {
            XCTAssertEqual(error as? TestActivationError, .failed)
        }

        XCTAssertEqual(manager.installProfileIds, [profileId])
        XCTAssertNil(statusStore.lastSuccessDate)
        XCTAssertEqual(statusStore.lastFailureReason, TestActivationError.failed.localizedDescription)
    }

    func testReleaseManifestAcceptsCosmeticShardAssets() throws {
        let data = Data(
            """
            {
              "schemaVersion": 1,
              "releaseVersion": "20260622T092419Z-a051bbb856ea",
              "generatedAt": "2026-06-22T09:24:19Z",
              "repository": {
                "owner": "FedyaLight",
                "name": "sumi-protection-bundles",
                "commit": "a4fd0fa553180d8af4184d1dd0debb96632f83af"
              },
              "compatibility": {
                "minimumSumiBundleExpectationVersion": 1,
                "maximumSumiBundleExpectationVersion": 1,
                "bundleManifestSchemaVersion": 1,
                "requiredNativeCSSSafetyPolicyVersion": "sumi-native-css-safety/0.4"
              },
              "bundles": [
                {
                  "profileId": "adguardAdsPrivacy",
                  "bundleId": "bundle",
                  "generationId": "generation",
                  "generatedDate": "2026-06-22T09:24:19Z",
                  "groups": [
                    {
                      "id": "cosmetic",
                      "status": "generated",
                      "ruleCount": 1,
                      "shardCount": 1,
                      "assetNames": ["adguardAdsPrivacy-cosmetic-0001.json"]
                    }
                  ],
                  "assetNames": ["adguardAdsPrivacy-cosmetic-0001.json"]
                }
              ],
              "assets": [
                {
                  "name": "adguardAdsPrivacy-cosmetic-0001.json",
                  "role": "cosmeticShard",
                  "bundleProfileId": "adguardAdsPrivacy",
                  "groupId": "cosmetic",
                  "relativePath": "cosmetic/cosmetic-0001.json",
                  "byteSize": 2,
                  "sha256": "4f53cda18c2baa0c0354bb5f9a3ecbe5ed12ab4d8e54d5f98c302bbf3d032d89"
                }
              ]
            }
            """.utf8
        )

        let manifest = try JSONDecoder().decode(SumiProtectionBundleReleaseManifest.self, from: data)

        XCTAssertEqual(manifest.assets.first?.role, .cosmeticShard)
    }

    func testCosmeticJSShardsAreNotPublishedAsNativeNetworkRules() {
        let manifest = SumiAdblockNativeRuleBundleManifest(
            schemaVersion: 1,
            bundleId: "bundle",
            generationId: "generation",
            profileId: SumiProtectionBundleProfile.adblock,
            compiler: .init(name: "test", version: "1"),
            nativeCSSSafetyPolicyVersion: SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion,
            generatedDate: "2026-06-22T09:24:19Z",
            lists: [],
            profileLevelMapping: [
                "adblockMax": [.trackingNetwork, .adblockAdsPrivacyNetwork, .cosmetic],
            ],
            groups: [
                .init(
                    id: .cosmetic,
                    displayName: nil,
                    status: "generated",
                    activeLevels: ["adblockMax"],
                    ruleCount: 1,
                    shardCount: 1,
                    assetRelativePaths: ["cosmetic/cosmetic-0001.json"],
                    source: nil,
                    notes: []
                ),
            ],
            shards: [
                .init(
                    kind: "network",
                    group: "adblockAdsPrivacyNetwork",
                    logicalGroup: "adblockAdsPrivacyNetwork",
                    relativePath: "network/network-0001.json",
                    hash: "network-hash",
                    byteSize: 2,
                    ruleCount: 1,
                    webKitIdentifier: "network"
                ),
                .init(
                    kind: "cosmeticJS",
                    group: "cosmetic",
                    logicalGroup: "cosmetic",
                    relativePath: "cosmetic/cosmetic-0001.json",
                    hash: "cosmetic-hash",
                    byteSize: 2,
                    ruleCount: 1,
                    webKitIdentifier: "cosmetic"
                ),
            ],
            diagnosticsSummary: .init(
                inputRuleCount: 2,
                finalRuleCount: 2,
                finalShardCount: 2,
                networkRuleCount: 1,
                nativeCSSRuleCount: 0,
                unsafeCSSFilteredCount: 0,
                warnings: []
            ),
            unsafeCSSFilteredCount: 0,
            deduplication: .init(
                inputRawRuleCount: 2,
                rawDuplicateCountRemoved: 0,
                nativeJSONDuplicateCountRemoved: 0,
                skippedDedupeCount: 0,
                skippedDedupeReasons: [:],
                finalRuleCount: 2,
                finalShardCount: 2
            )
        )
        let bundle = SumiAdblockNativeRuleBundle(
            directoryURL: URL(fileURLWithPath: "/tmp/SumiAdblockBundle", isDirectory: true),
            manifest: manifest
        )

        let compiled = bundle.compiledGenerationManifest(
            previousManifest: nil,
            installedDate: Date(timeIntervalSince1970: 0)
        )

        XCTAssertEqual(compiled.networkShards.map(\.webKitIdentifier), ["network"])
        XCTAssertTrue(compiled.nativeCSSShards.isEmpty)
    }

    func testNativeShardStagingIgnoresCosmeticJSPayloads() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiProtectionBundleRemoteUpdateTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let bundleURL = root.appendingPathComponent("SumiAdblockBundle", isDirectory: true)
        let networkURL = bundleURL.appendingPathComponent("network/network-0001.json")
        let cosmeticURL = bundleURL.appendingPathComponent("cosmetic/cosmetic-0001.json")
        try FileManager.default.createDirectory(
            at: networkURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.createDirectory(
            at: cosmeticURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        let networkData = Data(#"[{"action":{"type":"block"},"trigger":{"url-filter":"example"}}]"#.utf8)
        let cosmeticData = Data(#"{"genericHide":[".ad"]}"#.utf8)
        try networkData.write(to: networkURL)
        try cosmeticData.write(to: cosmeticURL)
        let bundle = SumiAdblockNativeRuleBundle(
            directoryURL: bundleURL,
            manifest: Self.makeBundleManifest(
                networkHash: Self.sha256Hex(networkData),
                networkByteSize: networkData.count,
                cosmeticHash: Self.sha256Hex(cosmeticData),
                cosmeticByteSize: cosmeticData.count
            )
        )

        let staged = try bundle.stagedShardURLs()

        XCTAssertEqual(Array(staged.keys), ["network-0001"])
    }

    func testAdblockGenerationCleanupReportsOnlyRemovedDirectories() async throws {
        let fileManager = FileManager.default
        let root = fileManager.temporaryDirectory
            .appendingPathComponent("SumiProtectionBundleCleanupTests-\(UUID().uuidString)", isDirectory: true)
        defer { try? fileManager.removeItem(at: root) }
        let manifestStore = AdblockUpdateManifestStore(rootDirectory: root)
        let activeManifest = Self.makeCompiledManifest(
            bundleId: "active-bundle",
            generationId: "active-generation",
            profileId: SumiProtectionBundleProfile.adblock
        )
        try await manifestStore.commit(manifest: activeManifest, stagedCompiledShardURLs: [:])
        let staleGenerationURL = await manifestStore.generationDirectoryURL(generationId: "stale-generation")
        try fileManager.createDirectory(at: staleGenerationURL, withIntermediateDirectories: true)
        let staleFileURL = staleGenerationURL.appendingPathComponent("stale.json")
        try Data("[]".utf8).write(to: staleFileURL)
        let staleStagingURL = await manifestStore.stagingDirectoryURL()
            .appendingPathComponent("stale-staging", isDirectory: true)
        try fileManager.createDirectory(at: staleStagingURL, withIntermediateDirectories: true)
        try Data("[]".utf8).write(to: staleStagingURL.appendingPathComponent("stale.json"))
        let collector = AdblockGenerationGarbageCollector(
            manifestStore: manifestStore,
            contentRuleListStore: FakeAdblockCleanupRuleListStore(),
            fileManager: FileManager()
        )

        let report = await collector.cleanupAfterSuccessfulUpdate()

        let removedPaths = Set(report.removedFilePaths.map(Self.canonicalTemporaryPath))
        let expectedRemovedPaths = Set([staleGenerationURL, staleStagingURL].map {
            Self.canonicalTemporaryPath($0.path)
        })
        XCTAssertEqual(removedPaths, expectedRemovedPaths)
        XCTAssertTrue(report.diagnostics.isEmpty)
        XCTAssertFalse(fileManager.fileExists(atPath: staleGenerationURL.path))
        XCTAssertFalse(fileManager.fileExists(atPath: staleStagingURL.path))
    }

    private static func makeBundleManifest(
        networkHash: String,
        networkByteSize: Int,
        cosmeticHash: String,
        cosmeticByteSize: Int
    ) -> SumiAdblockNativeRuleBundleManifest {
        SumiAdblockNativeRuleBundleManifest(
            schemaVersion: 1,
            bundleId: "bundle",
            generationId: "generation",
            profileId: SumiProtectionBundleProfile.adblock,
            compiler: .init(name: "test", version: "1"),
            nativeCSSSafetyPolicyVersion: SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion,
            generatedDate: "2026-06-22T09:24:19Z",
            lists: [],
            profileLevelMapping: nil,
            groups: nil,
            shards: [
                .init(
                    kind: "network",
                    group: "adblockAdsPrivacyNetwork",
                    logicalGroup: "adblockAdsPrivacyNetwork",
                    relativePath: "network/network-0001.json",
                    hash: networkHash,
                    byteSize: networkByteSize,
                    ruleCount: 1,
                    webKitIdentifier: "network"
                ),
                .init(
                    kind: "cosmeticJS",
                    group: "cosmetic",
                    logicalGroup: "cosmetic",
                    relativePath: "cosmetic/cosmetic-0001.json",
                    hash: cosmeticHash,
                    byteSize: cosmeticByteSize,
                    ruleCount: 1,
                    webKitIdentifier: "cosmetic"
                ),
            ],
            diagnosticsSummary: .init(
                inputRuleCount: 2,
                finalRuleCount: 2,
                finalShardCount: 2,
                networkRuleCount: 1,
                nativeCSSRuleCount: 0,
                unsafeCSSFilteredCount: 0,
                warnings: []
            ),
            unsafeCSSFilteredCount: 0,
            deduplication: .init(
                inputRawRuleCount: 2,
                rawDuplicateCountRemoved: 0,
                nativeJSONDuplicateCountRemoved: 0,
                skippedDedupeCount: 0,
                skippedDedupeReasons: [:],
                finalRuleCount: 2,
                finalShardCount: 2
            )
        )
    }

    private static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func canonicalTemporaryPath(_ path: String) -> String {
        path.replacingOccurrences(of: "/private/var/", with: "/var/")
    }

    private static func signatureEnvelopeData(
        keyId: String,
        signedAsset: String,
        signature: Data
    ) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "schemaVersion": 1,
                "algorithm": "Ed25519",
                "keyId": keyId,
                "signedAsset": signedAsset,
                "signature": signature.base64EncodedString(),
            ],
            options: [.sortedKeys]
        )
    }

    private static func makeRemoteFetchResult(
        profileId: String,
        bundleId: String,
        generationId: String
    ) -> SumiProtectionRemoteBundleFetchResult {
        SumiProtectionRemoteBundleFetchResult(
            profileId: profileId,
            releaseVersion: "20260626T120000Z",
            releaseTag: "20260626T120000Z",
            releaseURL: "https://example.com/release",
            publishedDate: Date(timeIntervalSince1970: 1),
            manifestSignatureRequired: true,
            manifestSignatureVerified: true,
            signingKeyId: "test-key",
            signingKeyVersion: 1,
            bundleId: bundleId,
            generationId: generationId,
            bundleURL: URL(fileURLWithPath: "/tmp/SumiProtectionBundleLifecycleTests", isDirectory: true)
        )
    }

    private static func makeCompiledManifest(
        bundleId: String,
        generationId: String,
        profileId: String
    ) -> AdblockCompiledGenerationManifest {
        AdblockCompiledGenerationManifest(
            schemaVersion: 1,
            activeGenerationId: generationId,
            createdDate: Date(timeIntervalSince1970: 0),
            selectedFilterLists: [],
            networkShards: [],
            nativeCSSShards: [],
            nativeCompiler: nil,
            nativeCompilerSourceLists: nil,
            nativeLogicalGroups: nil,
            nativeCompilationSummary: nil,
            compilerDiagnosticsSummary: "test",
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 1),
            previousGenerationId: nil,
            generationSource: .remoteReleaseBundle,
            nativeRuleBundleId: bundleId,
            bundleProfileId: profileId,
            remoteMetadata: nil
        )
    }
}

@MainActor
private final class FakePreparedBundleManager: SumiProtectionPreparedBundleManaging {
    var activeManifest: AdblockCompiledGenerationManifest?
    var installManifest: AdblockCompiledGenerationManifest?
    var discovery: SumiPreparedAdblockBundleDiscovery
    private(set) var installProfileIds: [String] = []
    private(set) var restoreProfileIds: [String] = []

    init(
        activeManifest: AdblockCompiledGenerationManifest?,
        installManifest: AdblockCompiledGenerationManifest?
    ) {
        self.activeManifest = activeManifest
        self.installManifest = installManifest
        let profileId = installManifest?.bundleProfileId ?? SumiProtectionBundleProfile.adblock
        self.discovery = SumiPreparedAdblockBundleDiscovery(
            requiredProfileId: profileId,
            resolvedBundle: SumiPreparedAdblockBundleDiscovery.ResolvedBundle(
                source: .remoteReleaseBundle,
                bundleURL: URL(fileURLWithPath: "/tmp/SumiProtectionBundleLifecycleTests", isDirectory: true),
                profileId: profileId,
                bundleId: installManifest?.nativeRuleBundleId,
                generationId: installManifest?.activeGenerationId,
                remoteMetadata: nil
            ),
            searchedPaths: [
                SumiPreparedAdblockBundleSearchPath(
                    source: .remoteReleaseBundle,
                    path: "/tmp/SumiProtectionBundleLifecycleTests",
                    exists: true,
                    rejectionReason: nil
                ),
            ]
        )
    }

    func activeManifestIfLoaded() -> AdblockCompiledGenerationManifest? {
        activeManifest
    }

    func preparedNativeRuleBundleDiscovery(profileId _: String) -> SumiPreparedAdblockBundleDiscovery {
        discovery
    }

    func installPreparedNativeRuleBundle(profileId: String) async -> AdblockCompiledGenerationManifest? {
        installProfileIds.append(profileId)
        activeManifest = installManifest
        return installManifest
    }

    func restorePreparedNativeRuleBundleForStartup(profileId: String) async -> AdblockCompiledGenerationManifest? {
        restoreProfileIds.append(profileId)
        activeManifest = installManifest
        return installManifest
    }
}

private final class FakeBundleRemoteUpdater: SumiProtectionBundleRemoteUpdating, @unchecked Sendable {
    let result: Result<SumiProtectionRemoteBundleFetchResult, Error>

    init(result: Result<SumiProtectionRemoteBundleFetchResult, Error>) {
        self.result = result
    }

    func fetchLatestApprovedBundle(profileId _: String) async throws -> SumiProtectionRemoteBundleFetchResult {
        try result.get()
    }
}

@MainActor
private final class FakeAdblockCleanupRuleListStore: SumiContentRuleListCompiling, @unchecked Sendable {
    func lookUpContentRuleList(forIdentifier identifier: String) async -> WKContentRuleList? {
        nil
    }

    func canLookUpContentRuleList(forIdentifier identifier: String) async -> Bool {
        false
    }

    func compileContentRuleList(
        forIdentifier identifier: String,
        encodedContentRuleList: String
    ) async throws -> WKContentRuleList {
        throw TestActivationError.failed
    }

    func availableContentRuleListIdentifiers() async -> [String] {
        []
    }

    func removeContentRuleList(forIdentifier identifier: String) async throws {}
}

private enum TestActivationError: LocalizedError, Equatable {
    case failed

    var errorDescription: String? {
        "activation failed"
    }
}
