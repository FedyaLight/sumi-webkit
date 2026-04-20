import CoreGraphics
import XCTest
@testable import Sumi

final class SumiTextureRingMetricsTests: XCTestCase {
    func testTextureQuantizationMatchesZenSixteenthSteps() {
        XCTAssertEqual(SumiTextureRingMetrics.quantized(0.61), 0.625, accuracy: 0.0001)
        XCTAssertEqual(SumiTextureRingMetrics.quantized(1.0), 0.0, accuracy: 0.0001)
    }

    func testTextureHandlerPositionUsesCenteredRingPointForZeroValue() {
        let size = CGSize(width: 104, height: 104)
        let point = SumiTextureRingMetrics.handlerPoint(
            in: size,
            value: 0
        )

        let anchorPoint = SumiTextureRingMetrics.dotPoint(index: 4, in: size)
        XCTAssertEqual(point.x, anchorPoint.x, accuracy: 0.0001)
        XCTAssertEqual(point.y, anchorPoint.y, accuracy: 0.0001)
    }

    func testActiveSweepStartsAtZenIndexFour() {
        XCTAssertTrue(SumiTextureRingMetrics.isActive(index: 4, value: 0.25))
        XCTAssertTrue(SumiTextureRingMetrics.isActive(index: 5, value: 0.25))
        XCTAssertFalse(SumiTextureRingMetrics.isActive(index: 3, value: 0.25))
        XCTAssertFalse(SumiTextureRingMetrics.isActive(index: 9, value: 0.25))
    }
}
