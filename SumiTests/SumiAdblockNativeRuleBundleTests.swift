import Foundation
import XCTest

@testable import Sumi

final class SumiAdblockNativeRuleBundleTests: XCTestCase {
    func testBundledDirectoryURLSkipsMalformedCandidateAndReturnsFallbackMatch() throws {
        let resourceURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiAdblockNativeRuleBundleTests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock {
            if FileManager.default.fileExists(atPath: resourceURL.path) {
                try FileManager.default.removeItem(at: resourceURL)
            }
        }

        let profileId = SumiProtectionBundleProfile.adblock
        let malformedCandidate = resourceURL
            .appendingPathComponent("SumiAdblockBundles", isDirectory: true)
            .appendingPathComponent(profileId, isDirectory: true)
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)
        let fallbackCandidate = resourceURL
            .appendingPathComponent(profileId, isDirectory: true)
            .appendingPathComponent(SumiAdblockNativeRuleBundle.directoryName, isDirectory: true)

        try FileManager.default.createDirectory(at: malformedCandidate, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: fallbackCandidate, withIntermediateDirectories: true)
        try Data("{".utf8).write(
            to: malformedCandidate.appendingPathComponent(SumiAdblockNativeRuleBundle.manifestFileName)
        )
        try JSONEncoder()
            .encode(makeManifest(profileId: profileId))
            .write(to: fallbackCandidate.appendingPathComponent(SumiAdblockNativeRuleBundle.manifestFileName))

        let resolved = SumiAdblockNativeRuleBundle.bundledDirectoryURL(
            for: profileId,
            resourceURL: resourceURL
        )

        XCTAssertEqual(resolved?.standardizedFileURL, fallbackCandidate.standardizedFileURL)
    }

    private func makeManifest(profileId: String) -> SumiAdblockNativeRuleBundleManifest {
        SumiAdblockNativeRuleBundleManifest(
            schemaVersion: 1,
            bundleId: "test-bundle",
            generationId: "generation-\(UUID().uuidString)",
            profileId: profileId,
            compiler: .init(name: "SumiTests", version: "1"),
            nativeCSSSafetyPolicyVersion: SumiAdblockNativeRuleBundle.requiredNativeCSSSafetyPolicyVersion,
            generatedDate: "2026-06-26T00:00:00Z",
            lists: [],
            profileLevelMapping: nil,
            groups: nil,
            shards: [],
            diagnosticsSummary: .init(
                inputRuleCount: 0,
                finalRuleCount: 0,
                finalShardCount: 0,
                networkRuleCount: 0,
                nativeCSSRuleCount: 0,
                unsafeCSSFilteredCount: 0,
                warnings: []
            ),
            unsafeCSSFilteredCount: 0,
            deduplication: .init(
                inputRawRuleCount: 0,
                rawDuplicateCountRemoved: 0,
                nativeJSONDuplicateCountRemoved: 0,
                skippedDedupeCount: 0,
                skippedDedupeReasons: [:],
                finalRuleCount: 0,
                finalShardCount: 0
            )
        )
    }
}
