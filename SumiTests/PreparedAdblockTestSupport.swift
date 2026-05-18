import CryptoKit
import Foundation

@testable import Sumi

enum PreparedAdblockTestSupport {
    static let ddgTrackingSourceName = "DuckDuckGo Tracker Radar / TDS"
    static let ddgTrackingSourceURL = "https://staticcdn.duckduckgo.com/trackerblocking/v6/current/macos-tds.json"
    static let ddgTrackingSourceLicense = "CC BY-NC-SA 4.0"
    static let ddgTrackingSourceLicenseURL = "https://creativecommons.org/licenses/by-nc-sa/4.0/"
    static let ddgTrackingAttribution = "Derived from DuckDuckGo Tracker Radar / Tracker Data Set for non-commercial Sumi protection bundles under CC BY-NC-SA 4.0 share-alike terms."
    static let ddgTrackingSourceSha256 = "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"

    static func makeBundle(
        at bundleURL: URL,
        profileId: String = SumiProtectionBundleProfile.adblock,
        generationId: String = "prepared-generation",
        includeTrackingNetwork: Bool = true,
        includeNativeCSS: Bool = false,
        nativeCSSSafetyPolicyVersion: String = SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion
    ) throws {
        var shards: [[String: Any]] = []

        if includeTrackingNetwork {
            let trackingDirectory = bundleURL.appendingPathComponent("trackingNetwork", isDirectory: true)
            try FileManager.default.createDirectory(at: trackingDirectory, withIntermediateDirectories: true)

            let trackingData = Data(trackingRuleJSON().utf8)
            let trackingHash = sha256Hex(trackingData)
            try trackingData.write(to: trackingDirectory.appendingPathComponent("trackingNetwork-0001.json"))
            shards.append(
                [
                    "kind": "network",
                    "group": "trackingNetwork",
                    "logicalGroup": "trackingNetwork",
                    "relativePath": "trackingNetwork/trackingNetwork-0001.json",
                    "hash": trackingHash,
                    "byteSize": trackingData.count,
                    "ruleCount": 1,
                    "webKitIdentifier": "sumi.tracking.network.\(generationId).0001.\(trackingHash.prefix(12))",
                ]
            )
        }

        let networkDirectory = bundleURL.appendingPathComponent("network", isDirectory: true)
        try FileManager.default.createDirectory(at: networkDirectory, withIntermediateDirectories: true)

        let networkData = Data(networkRuleJSON().utf8)
        let networkHash = sha256Hex(networkData)
        try networkData.write(to: networkDirectory.appendingPathComponent("network-0001.json"))

        shards.append(
            [
                "kind": "network",
                "group": "adblockAdsPrivacyNetwork",
                "logicalGroup": "adblockAdsPrivacyNetwork",
                "relativePath": "network/network-0001.json",
                "hash": networkHash,
                "byteSize": networkData.count,
                "ruleCount": 1,
                "webKitIdentifier": "sumi.adblock.network.\(generationId).0001.\(networkHash.prefix(12))",
            ]
        )

        if includeNativeCSS {
            let cssDirectory = bundleURL.appendingPathComponent("nativeCSS", isDirectory: true)
            try FileManager.default.createDirectory(at: cssDirectory, withIntermediateDirectories: true)
            let cssData = Data(nativeCSSRuleJSON().utf8)
            let cssHash = sha256Hex(cssData)
            try cssData.write(to: cssDirectory.appendingPathComponent("nativeCSS-0001.json"))
            shards.append(
                [
                    "kind": "nativeCSS",
                    "group": "adblockAdsPrivacyNetwork",
                    "logicalGroup": "adblockAdsPrivacyNetwork",
                    "relativePath": "nativeCSS/nativeCSS-0001.json",
                    "hash": cssHash,
                    "byteSize": cssData.count,
                    "ruleCount": 1,
                    "webKitIdentifier": "sumi.adblock.nativeCSS.\(generationId).0001.\(cssHash.prefix(12))",
                ]
            )
        }

        let manifest: [String: Any] = [
            "schemaVersion": 1,
            "bundleId": "sumi.adblock.bundle.\(profileId).test",
            "generationId": generationId,
            "profileId": profileId,
            "profileLevelMapping": [
                "off": [],
                "protection": ["trackingNetwork"],
                "adblock": ["trackingNetwork", "adblockAdsPrivacyNetwork"],
            ],
            "groups": [
                [
                    "id": "trackingNetwork",
                    "displayName": "Tracking Network",
                    "status": includeTrackingNetwork ? "available" : "placeholder",
                    "ruleCount": includeTrackingNetwork ? 1 : 0,
                    "shardCount": includeTrackingNetwork ? 1 : 0,
                    "source": [
                        "type": "ddgTDS",
                        "name": "test-prepared-tracking",
                        "sourceName": ddgTrackingSourceName,
                        "url": ddgTrackingSourceURL,
                        "sourceURL": ddgTrackingSourceURL,
                        "license": ddgTrackingSourceLicense,
                        "sourceLicense": ddgTrackingSourceLicense,
                        "sourceLicenseURL": ddgTrackingSourceLicenseURL,
                        "attribution": ddgTrackingAttribution,
                        "generatedAt": "2026-05-17T00:00:00Z",
                        "sourceSha256": ddgTrackingSourceSha256,
                        "sourceByteSize": 1234,
                        "ruleCount": includeTrackingNetwork ? 1 : 0,
                        "shardCount": includeTrackingNetwork ? 1 : 0,
                        "nonCommercialOnly": true,
                        "shareAlike": true,
                        "generator": "sumi-ddg-tds-webkit/0.1 tracker-radar-kit-compatible",
                    ],
                    "deduplication": [
                        "exactDuplicatesRemoved": 0,
                        "safeToDedupe": true,
                    ],
                    "notes": includeTrackingNetwork ? [] : [
                        "trackingNetwork is intentionally missing for migration diagnostics coverage.",
                    ],
                ],
                [
                    "id": "adblockAdsPrivacyNetwork",
                    "displayName": "Adblock Ads Privacy Network",
                    "status": "available",
                    "ruleCount": 1,
                    "shardCount": 1,
                    "source": [
                        "name": "test-prepared-adblock",
                        "url": "https://example.test/adblock.txt",
                        "license": "test-fixture",
                    ],
                    "deduplication": [
                        "exactDuplicatesRemoved": 0,
                        "safeToDedupe": true,
                    ],
                    "notes": [],
                ],
            ],
            "compiler": [
                "name": "sumi-protection-bundles",
                "version": "test",
            ],
            "nativeCSSSafetyPolicyVersion": nativeCSSSafetyPolicyVersion,
            "generatedDate": "2026-05-17T00:00:00Z",
            "lists": [
                [
                    "id": profileId,
                    "displayName": profileId,
                    "url": "https://example.test/\(profileId).txt",
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
                "networkRuleCount": includeTrackingNetwork ? 2 : 1,
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

        let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
        try data.write(to: bundleURL.appendingPathComponent("manifest.json"))
        try Data("{}".utf8).write(to: bundleURL.appendingPathComponent("diagnostics.json"))
    }

    static func seedPreparedManifest(
        in store: AdblockUpdateManifestStore,
        profileId: String = SumiProtectionBundleProfile.adblock,
        generationId: String = "prepared-generation",
        previousGenerationId: String? = nil,
        generationSource: AdblockRuleGenerationSource = .developmentBundle,
        includeTrackingNetwork: Bool = true,
        includeNativeCSS: Bool = false
    ) async throws -> AdblockCompiledGenerationManifest {
        var networkShards: [NativeContentBlockingShardDescriptor] = []
        var shardDataById = [String: Data]()

        if includeTrackingNetwork {
            let trackingData = Data(trackingRuleJSON().utf8)
            let trackingHash = sha256Hex(trackingData)
            let trackingShard = shard(
                id: "trackingNetwork-0001",
                generationId: generationId,
                kind: .network,
                protectionGroup: .trackingNetwork,
                webKitIdentifier: "sumi.tracking.network.\(generationId).0001.\(trackingHash.prefix(12))",
                data: trackingData
            )
            networkShards.append(trackingShard)
            shardDataById[trackingShard.id] = trackingData
        }

        let networkData = Data(networkRuleJSON().utf8)
        let networkHash = sha256Hex(networkData)
        let networkShard = shard(
            id: "network-0001",
            generationId: generationId,
            kind: .network,
            protectionGroup: .adblockAdsPrivacyNetwork,
            webKitIdentifier: "sumi.adblock.network.\(generationId).0001.\(networkHash.prefix(12))",
            data: networkData
        )
        networkShards.append(networkShard)

        var nativeCSSShards: [NativeContentBlockingShardDescriptor] = []
        shardDataById[networkShard.id] = networkData
        if includeNativeCSS {
            let cssData = Data(nativeCSSRuleJSON().utf8)
            let cssHash = sha256Hex(cssData)
            let cssShard = shard(
                id: "nativeCSS-0001",
                generationId: generationId,
                kind: .nativeCosmeticCSS,
                protectionGroup: .adblockAdsPrivacyNetwork,
                webKitIdentifier: "sumi.adblock.nativeCSS.\(generationId).0001.\(cssHash.prefix(12))",
                data: cssData
            )
            nativeCSSShards = [cssShard]
            shardDataById[cssShard.id] = cssData
        }

        let manifest = AdblockCompiledGenerationManifest(
            schemaVersion: 6,
            activeGenerationId: generationId,
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            selectedFilterLists: [
                AdblockCompiledGenerationManifest.SelectedFilterList(
                    id: profileId,
                    displayName: profileId,
                    contentHash: "\(profileId)-hash"
                ),
            ],
            networkShards: networkShards,
            nativeCSSShards: nativeCSSShards,
            nativeCompiler: NativeContentBlockingCompilerIdentity(
                name: "sumi-protection-bundles",
                version: "test"
            ),
            nativeCompilerSourceLists: [],
            nativeLogicalGroups: logicalGroups(includeTrackingNetwork: includeTrackingNetwork),
            compilerDiagnosticsSummary: "generationSource=\(generationSource.rawValue)",
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 1_700_000_000),
            previousGenerationId: previousGenerationId,
            generationSource: generationSource,
            nativeRuleBundleId: "sumi.adblock.bundle.\(profileId).test",
            bundleProfileId: profileId
        )

        let stagingDirectory = try await store.beginStaging()
        var stagedURLs: [String: URL] = [:]
        for (id, data) in shardDataById {
            let url = stagingDirectory.appendingPathComponent("\(id).json")
            try data.write(to: url)
            stagedURLs[id] = url
        }
        try await store.commit(manifest: manifest, stagedCompiledShardURLs: stagedURLs)
        return manifest
    }

    static func ruleList(identifier: String, filter: String) -> SumiContentRuleListDefinition {
        SumiContentRuleListDefinition(
            name: identifier,
            encodedContentRuleList: encodedNetworkRuleJSON(filter: filter),
            storeIdentifierOverride: identifier
        )
    }

    static func networkRuleJSON() -> String {
        encodedNetworkRuleJSON(filter: ".*ads\\\\.example/.*")
    }

    static func trackingRuleJSON() -> String {
        encodedNetworkRuleJSON(filter: ".*tracker\\\\.example/.*")
    }

    static func nativeCSSRuleJSON() -> String {
        """
        [
          {
            "trigger": {
              "url-filter": ".*"
            },
            "action": {
              "type": "css-display-none",
              "selector": ".ad-banner"
            }
          }
        ]
        """
    }

    static func encodedNetworkRuleJSON(filter: String) -> String {
        """
        [
          {
            "trigger": {
              "url-filter": "\(filter)"
            },
            "action": {
              "type": "block"
            }
          }
        ]
        """
    }

    static func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }

    private static func shard(
        id: String,
        generationId: String,
        kind: AdblockCompiledRuleGroupKind,
        protectionGroup: SumiProtectionGroupKind? = nil,
        webKitIdentifier: String,
        data: Data
    ) -> NativeContentBlockingShardDescriptor {
        NativeContentBlockingShardDescriptor(
            id: id,
            generationId: generationId,
            kind: kind,
            sourceListIdentifiers: [SumiProtectionBundleProfile.adblock],
            sourceCategories: [.baseAds],
            protectionGroup: protectionGroup,
            webKitIdentifier: webKitIdentifier,
            contentHash: sha256Hex(data),
            approximateRuleCount: 1,
            jsonByteCount: data.count,
            compilerIdentity: NativeContentBlockingCompilerIdentity(
                name: "sumi-protection-bundles",
                version: "test"
            ),
            diagnosticsSummary: "prepared-test"
        )
    }

    private static func logicalGroups(
        includeTrackingNetwork: Bool
    ) -> [NativeContentBlockingLogicalGroupDescriptor] {
        [
            NativeContentBlockingLogicalGroupDescriptor(
                id: .trackingNetwork,
                status: includeTrackingNetwork ? "available" : "placeholder",
                ruleCount: includeTrackingNetwork ? 1 : 0,
                shardCount: includeTrackingNetwork ? 1 : 0,
                sourceName: ddgTrackingSourceName,
                sourceURL: ddgTrackingSourceURL,
                sourceLicense: ddgTrackingSourceLicense,
                sourceLicenseURL: ddgTrackingSourceLicenseURL,
                sourceAttribution: ddgTrackingAttribution,
                sourceGeneratedAt: "2026-05-17T00:00:00Z",
                sourceSha256: ddgTrackingSourceSha256,
                sourceNonCommercialOnly: true,
                sourceShareAlike: true,
                sourceGenerator: "sumi-ddg-tds-webkit/0.1 tracker-radar-kit-compatible",
                notes: includeTrackingNetwork ? [] : [
                    "trackingNetwork is intentionally missing for migration diagnostics coverage.",
                ]
            ),
            NativeContentBlockingLogicalGroupDescriptor(
                id: .adblockAdsPrivacyNetwork,
                status: "available",
                ruleCount: 1,
                shardCount: 1,
                sourceName: "test-prepared-adblock",
                sourceURL: "https://example.test/adblock.txt",
                sourceLicense: "test-fixture",
                sourceLicenseURL: nil,
                sourceAttribution: nil,
                sourceGeneratedAt: nil,
                sourceSha256: nil,
                sourceNonCommercialOnly: nil,
                sourceShareAlike: nil,
                sourceGenerator: nil,
                notes: []
            ),
        ]
    }
}

@MainActor
final class PreparedBundleTrackingRuleSource: SumiTrackingProtectionRuleProviding {
    private(set) var callCount = 0
    private let definitions: [SumiContentRuleListDefinition]

    init(definitions: [SumiContentRuleListDefinition]) {
        self.definitions = definitions
    }

    func ruleLists(for policy: SumiTrackingProtectionPolicy) throws -> [SumiContentRuleListDefinition] {
        callCount += 1
        return policy.isFullyDisabled ? [] : definitions
    }
}
