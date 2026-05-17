import CryptoKit
import Foundation
import XCTest

@testable import Sumi

final class SumiProtectionBundleRemoteUpdateTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() async throws {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        try await super.tearDown()
    }

    func testRemoteUpdaterDownloadsVerifiesAndCommitsPreparedBundleCache() async throws {
        let root = temporaryDirectory()
        let fixture = try makeReleaseFixture(generationId: "remote-generation")
        let updater = SumiProtectionBundleRemoteUpdater(
            fetcher: fixture.fetcher,
            rootDirectory: root
        )

        let result = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
        let cached = try SumiAdblockNativeRuleBundle.load(directoryURL: result.bundleURL)
        let metadata = SumiRemoteAdblockBundleCache.remoteMetadata(bundleURL: result.bundleURL)

        XCTAssertEqual(result.releaseVersion, "20260517T000000Z-test")
        XCTAssertEqual(result.releaseTag, "bundles-20260517T000000Z-test")
        XCTAssertEqual(cached.manifest.profileId, SumiProtectionBundleProfile.adblock)
        XCTAssertEqual(cached.manifest.generationId, "remote-generation")
        XCTAssertEqual(metadata?.releaseVersion, result.releaseVersion)
    }

    func testRemoteUpdaterRejectsHashMismatchAndPreservesPreviousCache() async throws {
        let root = temporaryDirectory()
        let previousBundleURL = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: SumiProtectionBundleProfile.adblock,
            rootDirectory: root
        )
        try PreparedAdblockTestSupport.makeBundle(at: previousBundleURL, generationId: "previous-generation")
        let fixture = try makeReleaseFixture(
            generationId: "new-generation",
            tamperedAssetName: "\(SumiProtectionBundleProfile.adblock)-network-0001.json"
        )
        let updater = SumiProtectionBundleRemoteUpdater(
            fetcher: fixture.fetcher,
            rootDirectory: root
        )

        do {
            _ = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
            XCTFail("Expected hash mismatch")
        } catch let error as SumiProtectionBundleRemoteUpdateError {
            guard case .assetHashMismatch = error else {
                return XCTFail("Expected hash mismatch, got \(error)")
            }
        }

        let cached = try SumiAdblockNativeRuleBundle.load(directoryURL: previousBundleURL)
        XCTAssertEqual(cached.manifest.generationId, "previous-generation")
    }

    func testRemoteUpdaterRejectsIncompatibleReleaseManifestBeforeCaching() async throws {
        let root = temporaryDirectory()
        let fixture = try makeReleaseFixture(
            generationId: "new-generation",
            nativeCSSSafetyPolicyVersion: "unsupported-policy"
        )
        let updater = SumiProtectionBundleRemoteUpdater(
            fetcher: fixture.fetcher,
            rootDirectory: root
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
        }

        let cachedURL = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: SumiProtectionBundleProfile.adblock,
            rootDirectory: root
        )
        XCTAssertFalse(FileManager.default.fileExists(atPath: cachedURL.path))
    }

    private func makeReleaseFixture(
        generationId: String,
        tamperedAssetName: String? = nil,
        nativeCSSSafetyPolicyVersion: String = SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion
    ) throws -> ReleaseFixture {
        let sourceRoot = temporaryDirectory()
        let bundleURL = sourceRoot.appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(at: bundleURL, generationId: generationId)
        let bundle = try SumiAdblockNativeRuleBundle.load(directoryURL: bundleURL)
        let profileId = bundle.manifest.profileId

        var dataByName = [String: Data]()
        var assetDescriptors = [[String: Any]]()
        func appendAsset(name: String, role: String, relativePath: String, data: Data) {
            dataByName[name] = data
            assetDescriptors.append(
                [
                    "name": name,
                    "role": role,
                    "bundleProfileId": profileId,
                    "relativePath": relativePath,
                    "byteSize": data.count,
                    "sha256": sha256Hex(data),
                ]
            )
        }

        appendAsset(
            name: "\(profileId)-manifest.json",
            role: "bundleManifest",
            relativePath: "manifest.json",
            data: try Data(contentsOf: bundleURL.appendingPathComponent("manifest.json"))
        )
        appendAsset(
            name: "\(profileId)-diagnostics.json",
            role: "diagnostics",
            relativePath: "diagnostics.json",
            data: try Data(contentsOf: bundleURL.appendingPathComponent("diagnostics.json"))
        )
        for shard in bundle.manifest.shards {
            let name = "\(profileId)-\(URL(fileURLWithPath: shard.relativePath).lastPathComponent)"
            let data = try Data(contentsOf: bundleURL.appendingPathComponent(shard.relativePath))
            appendAsset(
                name: name,
                role: shard.kind == "nativeCSS" ? "nativeCSSShard" : "networkShard",
                relativePath: shard.relativePath,
                data: data
            )
        }

        if let tamperedAssetName, var tampered = dataByName[tamperedAssetName],
           let first = tampered.first {
            tampered[0] = first == 0 ? 1 : first ^ 0xff
            dataByName[tamperedAssetName] = tampered
        }

        let releaseManifest: [String: Any] = [
            "schemaVersion": 1,
            "releaseVersion": "20260517T000000Z-test",
            "generatedAt": "2026-05-17T00:00:00Z",
            "repository": [
                "owner": "FedyaLight",
                "name": "sumi-protection-bundles",
                "commit": "test",
            ],
            "compatibility": [
                "minimumSumiBundleExpectationVersion": 1,
                "maximumSumiBundleExpectationVersion": 1,
                "bundleManifestSchemaVersion": 1,
                "requiredNativeCSSSafetyPolicyVersion": nativeCSSSafetyPolicyVersion,
            ],
            "bundles": [
                [
                    "profileId": profileId,
                    "bundleId": bundle.manifest.bundleId,
                    "generationId": bundle.manifest.generationId,
                    "generatedDate": bundle.manifest.generatedDate,
                    "assetNames": assetDescriptors.compactMap { $0["name"] as? String },
                ],
            ],
            "assets": assetDescriptors,
        ]
        let releaseManifestData = try JSONSerialization.data(
            withJSONObject: releaseManifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        dataByName[SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName] = releaseManifestData

        let assets = dataByName.map { name, data in
            SumiProtectionBundleGitHubRelease.Asset(
                name: name,
                size: data.count,
                browserDownloadURL: URL(string: "https://example.test/\(name)")!,
                digest: "sha256:\(sha256Hex(data))"
            )
        }
        let dataByURL = Dictionary(
            uniqueKeysWithValues: dataByName.map { name, data in
                (URL(string: "https://example.test/\(name)")!, data)
            }
        )
        let release = SumiProtectionBundleGitHubRelease(
            tagName: "bundles-20260517T000000Z-test",
            htmlURL: "https://github.com/FedyaLight/sumi-protection-bundles/releases/tag/bundles-20260517T000000Z-test",
            draft: false,
            prerelease: false,
            publishedAt: "2026-05-17T00:00:00Z",
            assets: assets
        )
        return ReleaseFixture(fetcher: FakeReleaseFetcher(release: release, dataByURL: dataByURL))
    }

    private func temporaryDirectory() -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiProtectionBundleRemoteUpdateTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return directory
    }

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data)
            .map { String(format: "%02x", $0) }
            .joined()
    }
}

private struct ReleaseFixture {
    let fetcher: FakeReleaseFetcher
}

private final class FakeReleaseFetcher: SumiProtectionBundleReleaseFetching, @unchecked Sendable {
    let release: SumiProtectionBundleGitHubRelease
    let dataByURL: [URL: Data]

    init(release: SumiProtectionBundleGitHubRelease, dataByURL: [URL: Data]) {
        self.release = release
        self.dataByURL = dataByURL
    }

    func latestRelease() async throws -> SumiProtectionBundleGitHubRelease {
        release
    }

    func data(from url: URL) async throws -> Data {
        guard let data = dataByURL[url] else {
            throw SumiProtectionBundleRemoteUpdateError.assetMissing(url.lastPathComponent)
        }
        return data
    }
}

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error", file: file, line: line)
    } catch {}
}
