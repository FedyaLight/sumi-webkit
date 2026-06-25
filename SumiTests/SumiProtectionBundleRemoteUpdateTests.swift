import CryptoKit
import XCTest

@testable import Sumi

final class SumiProtectionBundleRemoteUpdateTests: XCTestCase {
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
}
