import XCTest

@testable import Sumi

final class SumiBoostEditorDotGeometryTests: XCTestCase {
    func testNormalizedDegreesWrapsIntoPositiveCircle() {
        XCTAssertEqual(SumiBoostEditorDotGeometry.normalizedDegrees(-10), 350, accuracy: 0.000_001)
        XCTAssertEqual(SumiBoostEditorDotGeometry.normalizedDegrees(370), 10, accuracy: 0.000_001)
    }

    func testPrimaryDotDataClampsDistanceAndDerivesSecondaryPosition() {
        let resolved = SumiBoostEditorDotGeometry.primaryDotData(
            for: SumiBoostDotPosition(x: 1, y: 0.5),
            secondaryDelta: 90
        )

        XCTAssertEqual(resolved.angle, 100, accuracy: 0.000_001)
        XCTAssertEqual(resolved.distance, 1, accuracy: 0.000_001)
        XCTAssertEqual(resolved.primary.x, 0.92, accuracy: 0.000_001)
        XCTAssertEqual(resolved.primary.y, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(resolved.secondary.x, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(resolved.secondary.y, 0.92, accuracy: 0.000_001)
    }

    func testSecondaryDotDataPreservesPrimaryDistanceAndReportsDelta() {
        let resolved = SumiBoostEditorDotGeometry.secondaryDotData(
            for: SumiBoostDotPosition(x: 0.5, y: 0.92),
            primaryAngle: 100,
            dotDistance: 1
        )

        XCTAssertEqual(resolved.delta, 90, accuracy: 0.000_001)
        XCTAssertEqual(resolved.position.x, 0.5, accuracy: 0.000_001)
        XCTAssertEqual(resolved.position.y, 0.92, accuracy: 0.000_001)
    }
}
