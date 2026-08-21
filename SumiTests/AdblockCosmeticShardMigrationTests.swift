import CryptoKit
import XCTest

@testable import Sumi

@MainActor
final class AdblockCosmeticShardMigrationTests: XCTestCase {
    func testMigratesInstalledGenerationAndStripsIfDomainCosmetics() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.commitOriginalGeneration()

        let migration = AdblockCosmeticShardMigration(archive: fixture.archive)
        let originalManifest = try await fixture.archive.activeManifest()
        let originalManifestUnwrapped = try XCTUnwrap(originalManifest)

        let migrated = await migration.migratedManifestIfPossible(
            for: originalManifestUnwrapped
        )

        // A new "-c1" generation was committed and becomes the active one.
        XCTAssertNotEqual(
            migrated.activeGenerationId,
            originalManifestUnwrapped.activeGenerationId
        )
        XCTAssertTrue(migrated.activeGenerationId.hasSuffix("-c1"))

        let cosmeticArtifact = migrated.advancedBlocking?.artifacts.first {
            $0.role == .domainCosmeticRules
        }
        XCTAssertNotNil(cosmeticArtifact)

        // The migrated shards no longer carry the domain cosmetic rule.
        let reader = AdblockArchivedShardReader(storageRoot: fixture.archive.storageRoot)
        let selectorSets: [[String?]] = try migrated.networkShards
            .sorted(by: { $0.id < $1.id })
            .map { shard in
                let data = try reader.rawValidatedData(for: shard)
                let rules = try JSONSerialization.jsonObject(with: data) as? [[String: Any]]
                return (rules ?? []).map {
                    ($0["action"] as? [String: Any])?["selector"] as? String
                }
            }
        XCTAssertEqual(selectorSets, [[nil], [], [".generic-ad"]])

        // The artifact payload carries the extracted selector.
        let artifactURL = try fixture.archive.advancedArtifactURL(
            generationID: migrated.activeGenerationId,
            relativePath: AdblockCosmeticDomainIndex.artifactRelativePath
        )
        let index = try AdblockCosmeticDomainIndex(
            data: Data(contentsOf: artifactURL)
        )
        XCTAssertEqual(index.selectors(forHost: "www.news.example"), [".domain-ad"])
        XCTAssertEqual(index.selectors(forHost: "other.example"), [])

        // Idempotent: an already-migrated manifest is returned unchanged.
        let secondPass = await migration.migratedManifestIfPossible(for: migrated)
        XCTAssertEqual(secondPass.activeGenerationId, migrated.activeGenerationId)
    }

    func testGenerationsWithoutAdvancedHalfAreLeftUntouched() async throws {
        let fixture = try Fixture()
        defer { fixture.remove() }
        try await fixture.commitOriginalGeneration(includeAdvanced: false)

        let migration = AdblockCosmeticShardMigration(archive: fixture.archive)
        let originalManifest = try await fixture.archive.activeManifest()
        let migrated = await migration.migratedManifestIfPossible(
            for: try XCTUnwrap(originalManifest)
        )
        XCTAssertEqual(migrated, originalManifest)
    }
}

@MainActor
private final class Fixture {
    let root: URL
    let archive: AdblockGenerationArchive
    private let sources: [String: URL]

    init() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent(
                "AdblockCosmeticMigration-\(UUID().uuidString)",
                isDirectory: true
            )
        try FileManager.default.createDirectory(
            at: root,
            withIntermediateDirectories: true
        )
        archive = AdblockGenerationArchive(rootDirectory: root)
        sources = [:]
    }

    var storageRoot: URL { archive.storageRoot }

    func commitOriginalGeneration(includeAdvanced: Bool = true) async throws {
        let networkRuleSets: [[[String: Any]]] = [
            [
                [
                    "action": ["type": "block"],
                    "trigger": ["url-filter": "||ads.example^"],
                ],
            ],
            [
                [
                    "action": ["type": "css-display-none", "selector": ".domain-ad"],
                    "trigger": ["url-filter": ".*", "if-domain": ["*news.example"]],
                ],
            ],
            [
                [
                    "action": ["type": "css-display-none", "selector": ".generic-ad"],
                    "trigger": ["url-filter": ".*"],
                ],
            ],
        ]
        var stagedShards = [String: URL]()
        var shardDescriptors = [NativeContentBlockingShardDescriptor]()
        for (index, ruleSet) in networkRuleSets.enumerated() {
            let data = try JSONSerialization.data(withJSONObject: ruleSet)
            let source = root
                .appendingPathComponent("Staging", isDirectory: true)
                .appendingPathComponent("network-000\(index + 1).json")
            try FileManager.default.createDirectory(
                at: source.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            try data.write(to: source)
            let digest = SHA256.hash(data: data)
                .map { String(format: "%02x", $0) }
                .joined()
            stagedShards["network-000\(index + 1)"] = source
            shardDescriptors.append(NativeContentBlockingShardDescriptor(
                id: "network-000\(index + 1)",
                generationId: "gen-a",
                kind: .network,
                protectionGroup: .adblockAdsPrivacyNetwork,
                webKitIdentifier: "sumi.adblock.test.a.\(index + 1).\(digest.prefix(8))",
                contentHash: digest,
                approximateRuleCount: ruleSet.count,
                jsonByteCount: data.count
            ))
        }

        var advanced: AdvancedBlockingGenerationDescriptor?
        if includeAdvanced {
            let webext = root.appendingPathComponent("webext-src", isDirectory: true)
            try FileManager.default.createDirectory(
                at: webext,
                withIntermediateDirectories: true
            )
            let artifactsData: [(AdvancedBlockingArtifactRole, String, Data)] = [
                (.ruleStorage, ".webext/rules.bin", Data("rules".utf8)),
                (.engineIndex, ".webext/engine.bin", Data("engine".utf8)),
                (.engineMetadata, ".webext/meta.bin", Data("meta".utf8)),
                (.sourceRules, ".webext/rules.txt", Data("source".utf8)),
                (.urlCleaningRules, ".webext/removeparam.json", Data("[]".utf8)),
            ]
            let artifacts = try artifactsData.map { role, path, data in
                let url = webext.appendingPathComponent(path)
                try FileManager.default.createDirectory(
                    at: url.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                try data.write(to: url)
                return AdvancedBlockingGenerationDescriptor.Artifact(
                    role: role,
                    relativePath: path,
                    hash: Self.sha256(data),
                    byteSize: data.count
                )
            }
            advanced = AdvancedBlockingGenerationDescriptor(
                format: AdvancedBlockingGenerationDescriptor.safariConverterFormat,
                schemaVersion: 1,
                runtimeVersion: "4.3.0",
                ruleCount: 1,
                artifacts: artifacts
            )
        }

        let manifest = AdblockCompiledGenerationManifest(
            schemaVersion: AdblockCompiledGenerationManifest.currentSchemaVersion,
            activeGenerationId: "gen-a",
            selectedFilterLists: [],
            networkShards: shardDescriptors,
            advancedBlocking: advanced,
            lastSuccessfulUpdateDate: Date(timeIntervalSince1970: 0),
            bundleProfileId: SumiProtectionBundleProfile.adblock
        )
        _ = sources
        try await archive.commit(
            manifest: manifest,
            stagedCompiledShardURLs: stagedShards,
            stagedAdvancedArtifactURLs: includeAdvanced
                ? advancedArtifactSources()
                : [:]
        )
    }

    private func advancedArtifactSources() throws -> [String: URL] {
        let directory = root.appendingPathComponent("webext-src", isDirectory: true)
        var result = [String: URL]()
        for role in [
            ".webext/rules.bin",
            ".webext/engine.bin",
            ".webext/meta.bin",
            ".webext/rules.txt",
            ".webext/removeparam.json",
        ] {
            result[role] = directory.appendingPathComponent(role)
        }
        return result
    }

    static func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func remove() {
        try? FileManager.default.removeItem(at: root)
    }
}
