import Foundation
import XCTest

@testable import Sumi

final class SumiAdblockNativeRuleBundleTests: XCTestCase {
    func testRepeatedGenerationDoesNotReferenceItselfAsPrevious() {
        let bundle = makeManifest(
            profileId: SumiProtectionBundleProfile.adblock,
            generationId: "stable-generation"
        )
        let projector = SumiAdblockNativeGenerationProjector()
        let active = projector.compiledManifest(
            from: bundle,
            previousManifest: nil,
            installedDate: Date(timeIntervalSince1970: 1)
        )

        let repeated = projector.compiledManifest(
            from: bundle,
            previousManifest: active,
            installedDate: Date(timeIntervalSince1970: 2)
        )

        XCTAssertNil(repeated.previousGenerationId)
    }

    private func makeManifest(
        profileId: String,
        generationId: String = "generation-\(UUID().uuidString)"
    ) -> SumiAdblockNativeRuleBundleManifest {
        SumiAdblockNativeRuleBundleManifest(
            schemaVersion: 1,
            bundleId: "test-bundle",
            generationId: generationId,
            profileId: profileId,
            lists: [],
            shards: [],
            advancedBlocking: nil
        )
    }
}
