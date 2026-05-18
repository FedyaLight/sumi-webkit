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
            signatureVerifier: fixture.signatureVerifier,
            rootDirectory: root
        )

        let result = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
        let cached = try SumiAdblockNativeRuleBundle.load(directoryURL: result.bundleURL)
        let metadata = SumiRemoteAdblockBundleCache.remoteMetadata(bundleURL: result.bundleURL)

        XCTAssertEqual(result.releaseVersion, "20260517T000000Z-test")
        XCTAssertEqual(result.releaseTag, "bundles-20260517T000000Z-test")
        XCTAssertEqual(cached.manifest.profileId, SumiProtectionBundleProfile.adblock)
        XCTAssertEqual(cached.manifest.generationId, "remote-generation")
        let trackingGroup = try XCTUnwrap(cached.manifest.groups?.first { $0.id == .trackingNetwork })
        XCTAssertEqual(trackingGroup.source?.sourceName, PreparedAdblockTestSupport.ddgTrackingSourceName)
        XCTAssertEqual(trackingGroup.source?.sourceLicense, PreparedAdblockTestSupport.ddgTrackingSourceLicense)
        XCTAssertEqual(trackingGroup.source?.sourceLicenseURL, PreparedAdblockTestSupport.ddgTrackingSourceLicenseURL)
        XCTAssertEqual(metadata?.releaseVersion, result.releaseVersion)
        XCTAssertEqual(metadata?.manifestSignatureVerified, true)
        XCTAssertEqual(metadata?.signingKeyId, fixture.signingKey.id)
    }

    func testRemoteUpdaterRejectsUnsignedManifest() async throws {
        let root = temporaryDirectory()
        let fixture = try makeReleaseFixture(generationId: "remote-generation", includeSignature: false)
        let updater = SumiProtectionBundleRemoteUpdater(
            fetcher: fixture.fetcher,
            signatureVerifier: fixture.signatureVerifier,
            rootDirectory: root
        )

        do {
            _ = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
            XCTFail("Expected missing signature")
        } catch let error as SumiProtectionBundleRemoteUpdateError {
            guard case .releaseManifestSignatureAssetMissing = error else {
                return XCTFail("Expected missing signature, got \(error)")
            }
        }
    }

    func testRemoteUpdaterRejectsInvalidSignature() async throws {
        let root = temporaryDirectory()
        let fixture = try makeReleaseFixture(generationId: "remote-generation", corruptSignature: true)
        let updater = SumiProtectionBundleRemoteUpdater(
            fetcher: fixture.fetcher,
            signatureVerifier: fixture.signatureVerifier,
            rootDirectory: root
        )

        do {
            _ = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
            XCTFail("Expected invalid signature")
        } catch let error as SumiProtectionBundleRemoteUpdateError {
            guard case .signatureInvalid = error else {
                return XCTFail("Expected invalid signature, got \(error)")
            }
        }
    }

    func testRemoteUpdaterRejectsModifiedManifestAfterSigning() async throws {
        let root = temporaryDirectory()
        let fixture = try makeReleaseFixture(generationId: "remote-generation", mutateManifestAfterSigning: true)
        let updater = SumiProtectionBundleRemoteUpdater(
            fetcher: fixture.fetcher,
            signatureVerifier: fixture.signatureVerifier,
            rootDirectory: root
        )

        do {
            _ = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
            XCTFail("Expected invalid signature")
        } catch let error as SumiProtectionBundleRemoteUpdateError {
            guard case .signatureInvalid = error else {
                return XCTFail("Expected invalid signature, got \(error)")
            }
        }
    }

    func testPinnedProductionSigningKeyVerifiesFixtureSignatureAndRejectsTampering() throws {
        let verifier = SumiProtectionBundleSignatureVerifier()
        let manifestData = Data((#"{"fixture":"sumi-production-signing-key-v1","schemaVersion":1}"# + "\n").utf8)
        let signatureJSON = #"""
        {
          "algorithm" : "Ed25519",
          "keyId" : "sumi-protection-bundles-ed25519-v1",
          "schemaVersion" : 1,
          "signature" : "7pmzjFXq+A/VTXOaQ2xzithpa7Tp5h51RCoXy9vUE7CA+2e+HBXqokmV36ldjrMAI9Fdy8bmGWItRY7utjgxDw==",
          "signedAsset" : "sumi-protection-bundles-release.json"
        }
        """#
        let signatureData = Data(signatureJSON.utf8)

        let verification = try verifier.verify(
            manifestData: manifestData,
            signatureData: signatureData,
            expectedSignedAsset: SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName
        )
        XCTAssertEqual(verification.keyId, "sumi-protection-bundles-ed25519-v1")
        XCTAssertEqual(verification.keyVersion, 1)

        var modifiedManifestData = manifestData
        modifiedManifestData.append(contentsOf: [0])
        XCTAssertThrowsError(
            try verifier.verify(
                manifestData: modifiedManifestData,
                signatureData: signatureData,
                expectedSignedAsset: SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName
            )
        ) { error in
            guard case .signatureInvalid = error as? SumiProtectionBundleRemoteUpdateError else {
                return XCTFail("Expected invalid signature for modified manifest, got \(error)")
            }
        }

        let wrongSignatureData = Data(signatureJSON.replacingOccurrences(of: "\"7pmz", with: "\"Apmz").utf8)
        XCTAssertThrowsError(
            try verifier.verify(
                manifestData: manifestData,
                signatureData: wrongSignatureData,
                expectedSignedAsset: SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName
            )
        ) { error in
            guard case .signatureInvalid = error as? SumiProtectionBundleRemoteUpdateError else {
                return XCTFail("Expected invalid signature for wrong signature, got \(error)")
            }
        }
    }

    func testRemoteUpdaterRejectsUnknownSigningKey() async throws {
        let root = temporaryDirectory()
        let fixture = try makeReleaseFixture(
            generationId: "remote-generation",
            keyId: "sumi-protection-bundles-ed25519-unknown"
        )
        let updater = SumiProtectionBundleRemoteUpdater(
            fetcher: fixture.fetcher,
            signatureVerifier: fixture.signatureVerifier,
            rootDirectory: root
        )

        do {
            _ = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
            XCTFail("Expected unknown key")
        } catch let error as SumiProtectionBundleRemoteUpdateError {
            guard case .signatureKeyUnknown = error else {
                return XCTFail("Expected unknown key, got \(error)")
            }
        }
    }

    func testRemoteUpdaterRejectsOlderSignedReleaseAsDowngrade() async throws {
        let root = temporaryDirectory()
        let previousBundleURL = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: SumiProtectionBundleProfile.adblock,
            rootDirectory: root
        )
        try PreparedAdblockTestSupport.makeBundle(at: previousBundleURL, generationId: "previous-generation")
        try writeRemoteMetadata(
            bundleURL: previousBundleURL,
            releaseVersion: "20260518T000000Z-test"
        )
        let fixture = try makeReleaseFixture(
            generationId: "remote-generation",
            releaseVersion: "20260517T000000Z-test"
        )
        let updater = SumiProtectionBundleRemoteUpdater(
            fetcher: fixture.fetcher,
            signatureVerifier: fixture.signatureVerifier,
            rootDirectory: root
        )

        do {
            _ = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
            XCTFail("Expected downgrade rejection")
        } catch let error as SumiProtectionBundleRemoteUpdateError {
            guard case .releaseDowngradeRejected = error else {
                return XCTFail("Expected downgrade rejection, got \(error)")
            }
        }

        let cached = try SumiAdblockNativeRuleBundle.load(directoryURL: previousBundleURL)
        XCTAssertEqual(cached.manifest.generationId, "previous-generation")
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
            signatureVerifier: fixture.signatureVerifier,
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

    func testRemoteUpdaterRejectsAssetByteSizeMismatch() async throws {
        let root = temporaryDirectory()
        let fixture = try makeReleaseFixture(
            generationId: "new-generation",
            sizeMismatchAssetName: "\(SumiProtectionBundleProfile.adblock)-network-0001.json"
        )
        let updater = SumiProtectionBundleRemoteUpdater(
            fetcher: fixture.fetcher,
            signatureVerifier: fixture.signatureVerifier,
            rootDirectory: root
        )

        do {
            _ = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
            XCTFail("Expected size mismatch")
        } catch let error as SumiProtectionBundleRemoteUpdateError {
            guard case .assetSizeMismatch = error else {
                return XCTFail("Expected size mismatch, got \(error)")
            }
        }
    }

    func testSignatureFailurePreservesPreviousCache() async throws {
        let root = temporaryDirectory()
        let previousBundleURL = SumiRemoteAdblockBundleCache.bundleURL(
            profileId: SumiProtectionBundleProfile.adblock,
            rootDirectory: root
        )
        try PreparedAdblockTestSupport.makeBundle(at: previousBundleURL, generationId: "previous-generation")
        let fixture = try makeReleaseFixture(generationId: "new-generation", corruptSignature: true)
        let updater = SumiProtectionBundleRemoteUpdater(
            fetcher: fixture.fetcher,
            signatureVerifier: fixture.signatureVerifier,
            rootDirectory: root
        )

        await XCTAssertThrowsErrorAsync {
            _ = try await updater.fetchLatestApprovedBundle(profileId: SumiProtectionBundleProfile.adblock)
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
            signatureVerifier: fixture.signatureVerifier,
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
        releaseVersion: String = "20260517T000000Z-test",
        includeSignature: Bool = true,
        corruptSignature: Bool = false,
        mutateManifestAfterSigning: Bool = false,
        keyId: String = "sumi-protection-bundles-ed25519-v1",
        tamperedAssetName: String? = nil,
        sizeMismatchAssetName: String? = nil,
        nativeCSSSafetyPolicyVersion: String = SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion
    ) throws -> ReleaseFixture {
        let sourceRoot = temporaryDirectory()
        let bundleURL = sourceRoot.appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
        try PreparedAdblockTestSupport.makeBundle(at: bundleURL, generationId: generationId)
        let bundle = try SumiAdblockNativeRuleBundle.load(directoryURL: bundleURL)
        let profileId = bundle.manifest.profileId
        let privateKey = Curve25519.Signing.PrivateKey()
        let signingKey = SumiProtectionBundleSigningKey(
            id: "sumi-protection-bundles-ed25519-v1",
            version: 1,
            publicKeyBase64: privateKey.publicKey.rawRepresentation.base64EncodedString()
        )

        var dataByName = [String: Data]()
        var assetDescriptors = [[String: Any]]()
        func appendAsset(
            name: String,
            role: String,
            relativePath: String,
            data: Data,
            groupId: String? = nil
        ) {
            dataByName[name] = data
            var descriptor: [String: Any] = [
                "name": name,
                "role": role,
                "bundleProfileId": profileId,
                "relativePath": relativePath,
                "byteSize": data.count,
                "sha256": sha256Hex(data),
            ]
            if let groupId {
                descriptor["groupId"] = groupId
            }
            assetDescriptors.append(descriptor)
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
            let groupId = shard.logicalGroup ?? shard.group
            let role: String
            if shard.kind == "nativeCSS" {
                role = "nativeCSSShard"
            } else if groupId == SumiProtectionGroupKind.trackingNetwork.rawValue {
                role = "trackingNetworkShard"
            } else {
                role = "networkShard"
            }
            appendAsset(
                name: name,
                role: role,
                relativePath: shard.relativePath,
                data: data,
                groupId: groupId
            )
        }

        let releaseGroups = try (bundle.manifest.groups ?? []).map { group -> [String: Any] in
            let groupAssetNames: [String] = assetDescriptors.compactMap { descriptor -> String? in
                guard descriptor["groupId"] as? String == group.id.rawValue else { return nil }
                return descriptor["name"] as? String
            }
            var releaseGroup: [String: Any] = [
                "id": group.id.rawValue,
                "ruleCount": group.ruleCount,
                "shardCount": group.shardCount,
                "assetNames": groupAssetNames,
                "assetRelativePaths": group.assetRelativePaths ?? [],
                "notes": group.notes ?? [],
            ]
            if let status = group.status {
                releaseGroup["status"] = status
            }
            if let source = group.source {
                let sourceData = try JSONEncoder().encode(source)
                releaseGroup["source"] = try JSONSerialization.jsonObject(with: sourceData)
            }
            return releaseGroup
        }

        let releaseManifest: [String: Any] = [
            "schemaVersion": 1,
            "releaseVersion": releaseVersion,
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
                    "groups": releaseGroups,
                    "assetNames": assetDescriptors.compactMap { $0["name"] as? String },
                ],
            ],
            "assets": assetDescriptors,
        ]
        let releaseManifestData = try JSONSerialization.data(
            withJSONObject: releaseManifest,
            options: [.prettyPrinted, .sortedKeys]
        )
        let signedManifestData = releaseManifestData

        if let tamperedAssetName, var tampered = dataByName[tamperedAssetName],
           let first = tampered.first {
            tampered[0] = first == 0 ? 1 : first ^ 0xff
            dataByName[tamperedAssetName] = tampered
        }
        if let sizeMismatchAssetName, var tampered = dataByName[sizeMismatchAssetName] {
            tampered.append(0xff)
            dataByName[sizeMismatchAssetName] = tampered
        }

        if mutateManifestAfterSigning {
            var mutated = releaseManifest
            mutated["releaseVersion"] = "\(releaseVersion)-mutated"
            dataByName[SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName] = try JSONSerialization.data(
                withJSONObject: mutated,
                options: [.prettyPrinted, .sortedKeys]
            )
        } else {
            dataByName[SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName] = releaseManifestData
        }

        if includeSignature {
            var signature = try privateKey.signature(for: signedManifestData)
            if corruptSignature {
                signature[0] = signature[0] == 0 ? 1 : signature[0] ^ 0xff
            }
            let signatureMetadata: [String: Any] = [
                "schemaVersion": 1,
                "algorithm": "Ed25519",
                "keyId": keyId,
                "signedAsset": SumiProtectionBundleRemoteUpdateConstants.releaseManifestAssetName,
                "signature": signature.base64EncodedString(),
            ]
            dataByName[SumiProtectionBundleRemoteUpdateConstants.releaseManifestSignatureAssetName] = try JSONSerialization.data(
                withJSONObject: signatureMetadata,
                options: [.prettyPrinted, .sortedKeys]
            )
        }

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
            tagName: "bundles-\(releaseVersion)",
            htmlURL: "https://github.com/FedyaLight/sumi-protection-bundles/releases/tag/bundles-\(releaseVersion)",
            draft: false,
            prerelease: false,
            publishedAt: "2026-05-17T00:00:00Z",
            assets: assets
        )
        return ReleaseFixture(
            fetcher: FakeReleaseFetcher(release: release, dataByURL: dataByURL),
            signatureVerifier: SumiProtectionBundleSignatureVerifier(keys: [signingKey]),
            signingKey: signingKey
        )
    }

    private func writeRemoteMetadata(
        bundleURL: URL,
        releaseVersion: String
    ) throws {
        let metadata = SumiAdblockPreparedBundleRemoteMetadata(
            releaseVersion: releaseVersion,
            releaseTag: "bundles-\(releaseVersion)",
            manifestSignatureRequired: true,
            manifestSignatureVerified: true,
            signingKeyId: "sumi-protection-bundles-ed25519-v1",
            signingKeyVersion: 1
        )
        let data = try JSONEncoder().encode(metadata)
        try data.write(to: bundleURL.appendingPathComponent(SumiRemoteAdblockBundleCache.metadataFileName))
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
    let signatureVerifier: SumiProtectionBundleSignatureVerifier
    let signingKey: SumiProtectionBundleSigningKey
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
