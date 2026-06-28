@testable import Sumi
import XCTest

final class SumiBackgroundMediaOptimizationPolicyTests: XCTestCase {
    func testUnknownWindowIsTreatedAsVisible() {
        XCTAssertTrue(SumiWindowVisibilityState.unknown.isEffectivelyVisible)
    }

    func testOccludedWindowIsNotEffectivelyVisible() {
        let state = SumiWindowVisibilityState(
            hasAttachedWindow: true,
            isVisible: true,
            isMiniaturized: false,
            isOccluded: true
        )

        XCTAssertFalse(state.isEffectivelyVisible)
    }

    func testMiniaturizedWindowIsNotEffectivelyVisible() {
        let state = SumiWindowVisibilityState(
            hasAttachedWindow: true,
            isVisible: true,
            isMiniaturized: true,
            isOccluded: false
        )

        XCTAssertFalse(state.isEffectivelyVisible)
    }

    func testHiddenAudibleTabPreservesAudio() {
        let policy = SumiBackgroundMediaOptimizationPolicy.make(energySaverActive: false)

        XCTAssertEqual(
            policy.mode(isVisible: false, isEligible: true, isAudible: true),
            .hiddenPreserveAudio
        )
    }

    func testHiddenSilentTabPausesSilentVideo() {
        let policy = SumiBackgroundMediaOptimizationPolicy.make(energySaverActive: false)

        XCTAssertEqual(
            policy.mode(isVisible: false, isEligible: true, isAudible: false),
            .hiddenPauseSilentVideo
        )
    }

    func testVisibleOrIneligibleTabRestoresVisibleMode() {
        let policy = SumiBackgroundMediaOptimizationPolicy.make(energySaverActive: false)

        XCTAssertEqual(
            policy.mode(isVisible: true, isEligible: true, isAudible: true),
            .visible
        )
        XCTAssertEqual(
            policy.mode(isVisible: false, isEligible: false, isAudible: true),
            .visible
        )
    }

    func testEnergySaverUsesShorterGraceInterval() {
        let normal = SumiBackgroundMediaOptimizationPolicy.make(energySaverActive: false)
        let energySaver = SumiBackgroundMediaOptimizationPolicy.make(energySaverActive: true)

        XCTAssertEqual(normal.hiddenGraceMilliseconds, 10_000)
        XCTAssertEqual(energySaver.hiddenGraceMilliseconds, 2_000)
    }
}
