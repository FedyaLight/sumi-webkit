import CryptoKit
import Foundation

@testable import Sumi

enum PreparedAdblockTestSupport {
    static func makeBundle(
        at bundleURL: URL,
        profileId: String = SumiProtectionBundleProfile.adblock,
        generationId: String = "prepared-generation",
        includeNativeCSS: Bool = false,
        nativeCSSSafetyPolicyVersion: String = SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion
    ) throws {
        let networkDirectory = bundleURL.appendingPathComponent("network", isDirectory: true)
        try FileManager.default.createDirectory(at: networkDirectory, withIntermediateDirectories: true)

        let networkData = Data(networkRuleJSON().utf8)
        let networkHash = sha256Hex(networkData)
        try networkData.write(to: networkDirectory.appendingPathComponent("network-0001.json"))

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
            let cssDirectory = bundleURL.appendingPathComponent("nativeCSS", isDirectory: true)
            try FileManager.default.createDirectory(at: cssDirectory, withIntermediateDirectories: true)
            let cssData = Data(nativeCSSRuleJSON().utf8)
            let cssHash = sha256Hex(cssData)
            try cssData.write(to: cssDirectory.appendingPathComponent("nativeCSS-0001.json"))
            shards.append(
                [
                    "kind": "nativeCSS",
                    "group": "nativeCSS",
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
        includeNativeCSS: Bool = false
    ) async throws -> AdblockCompiledGenerationManifest {
        let networkData = Data(networkRuleJSON().utf8)
        let networkHash = sha256Hex(networkData)
        let networkShard = shard(
            id: "network-0001",
            generationId: generationId,
            kind: .network,
            webKitIdentifier: "sumi.adblock.network.\(generationId).0001.\(networkHash.prefix(12))",
            data: networkData
        )

        var nativeCSSShards: [NativeContentBlockingShardDescriptor] = []
        var shardDataById = [networkShard.id: networkData]
        if includeNativeCSS {
            let cssData = Data(nativeCSSRuleJSON().utf8)
            let cssHash = sha256Hex(cssData)
            let cssShard = shard(
                id: "nativeCSS-0001",
                generationId: generationId,
                kind: .nativeCosmeticCSS,
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
            networkShards: [networkShard],
            nativeCSSShards: nativeCSSShards,
            nativeCompiler: NativeContentBlockingCompilerIdentity(
                name: "sumi-protection-bundles",
                version: "test"
            ),
            nativeCompilerSourceLists: [],
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
        webKitIdentifier: String,
        data: Data
    ) -> NativeContentBlockingShardDescriptor {
        NativeContentBlockingShardDescriptor(
            id: id,
            generationId: generationId,
            kind: kind,
            sourceListIdentifiers: [SumiProtectionBundleProfile.adblock],
            sourceCategories: [.baseAds],
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
