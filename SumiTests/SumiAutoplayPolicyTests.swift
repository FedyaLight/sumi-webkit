import WebKit
import XCTest

@testable import Sumi

final class SumiAutoplayPolicyTests: XCTestCase {
    func testWebKitMappingIsDeterministic() {
        XCTAssertEqual(SumiAutoplayPolicy.default.mediaTypesRequiringUserActionForPlayback, [])
        XCTAssertEqual(SumiAutoplayPolicy.allowAll.mediaTypesRequiringUserActionForPlayback, [])
        XCTAssertEqual(SumiAutoplayPolicy.blockAudible.mediaTypesRequiringUserActionForPlayback, .audio)
        XCTAssertEqual(SumiAutoplayPolicy.blockAll.mediaTypesRequiringUserActionForPlayback, .all)
    }

    func testRuntimeMappingUsesBlockAudibleName() {
        XCTAssertEqual(SumiAutoplayPolicy.default.runtimeState, .allowAll)
        XCTAssertEqual(SumiAutoplayPolicy.allowAll.runtimeState, .allowAll)
        XCTAssertEqual(SumiAutoplayPolicy.blockAudible.runtimeState, .blockAudible)
        XCTAssertEqual(SumiAutoplayPolicy.blockAll.runtimeState, .blockAll)
    }

    func testMetadataMappingIsDeterministic() throws {
        XCTAssertNil(SumiAutoplayDecisionMapper.decision(for: .default, source: .user))

        let allow = try XCTUnwrap(
            SumiAutoplayDecisionMapper.decision(for: .allowAll, source: .user)
        )
        XCTAssertEqual(allow.state, .allow)
        XCTAssertEqual(allow.metadata?[SumiAutoplayDecisionMapper.metadataKey], "allowAll")
        XCTAssertEqual(SumiAutoplayDecisionMapper.policy(from: allow), .allowAll)

        let blockAudible = try XCTUnwrap(
            SumiAutoplayDecisionMapper.decision(for: .blockAudible, source: .user)
        )
        XCTAssertEqual(blockAudible.state, .deny)
        XCTAssertEqual(blockAudible.metadata?[SumiAutoplayDecisionMapper.metadataKey], "blockAudible")
        XCTAssertEqual(SumiAutoplayDecisionMapper.policy(from: blockAudible), .blockAudible)

        let blockAll = try XCTUnwrap(
            SumiAutoplayDecisionMapper.decision(for: .blockAll, source: .user)
        )
        XCTAssertEqual(blockAll.state, .deny)
        XCTAssertEqual(blockAll.metadata?[SumiAutoplayDecisionMapper.metadataKey], "blockAll")
        XCTAssertEqual(SumiAutoplayDecisionMapper.policy(from: blockAll), .blockAll)
    }

    func testLegacyLikeDecisionWithoutMetadataFallsBackDeterministically() {
        let allow = SumiPermissionDecision(
            state: .allow,
            persistence: .persistent,
            source: .user
        )
        let deny = SumiPermissionDecision(
            state: .deny,
            persistence: .persistent,
            source: .user
        )
        let ask = SumiPermissionDecision(
            state: .ask,
            persistence: .persistent,
            source: .user
        )

        XCTAssertEqual(SumiAutoplayDecisionMapper.policy(from: allow), .allowAll)
        XCTAssertEqual(SumiAutoplayDecisionMapper.policy(from: deny), .blockAudible)
        XCTAssertEqual(SumiAutoplayDecisionMapper.policy(from: ask), .default)
    }

    func testDisplayLabelsDoNotPromiseMuting() {
        XCTAssertFalse(SumiAutoplayPolicy.blockAudible.displayLabel.lowercased().contains("mute"))
        XCTAssertFalse(SumiAutoplayPolicy.blockAudible.siteControlsSubtitle.lowercased().contains("mute"))
    }
}
