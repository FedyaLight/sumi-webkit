import CoreGraphics
import XCTest
@testable import Sumi

final class SumiOpacityWaveMetricsTests: XCTestCase {
    func testWaveEndpointsMatchZenReferencePaths() {
        XCTAssertEqual(
            SumiOpacityWaveMetrics.interpolatedPathString(progress: 0),
            SumiOpacityWaveMetrics.linePathString
        )
        XCTAssertEqual(
            SumiOpacityWaveMetrics.interpolatedPathString(progress: 1),
            SumiOpacityWaveMetrics.sinePathString
        )
    }

    func testThumbSizingMatchesZenRange() {
        XCTAssertEqual(
            SumiOpacityWaveMetrics.thumbSize(for: 0),
            CGSize(width: 10, height: 40)
        )
        XCTAssertEqual(
            SumiOpacityWaveMetrics.thumbSize(for: 1),
            CGSize(width: 25, height: 55)
        )
    }

    func testOpacityNormalizationMatchesMacOSZenRange() {
        XCTAssertEqual(
            SumiOpacityWaveMetrics.normalizedProgress(for: WorkspaceGradientTheme.minimumOpacity),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SumiOpacityWaveMetrics.normalizedProgress(for: WorkspaceGradientTheme.maximumOpacity),
            1,
            accuracy: 0.0001
        )
    }

    func testInteractiveLineBoundsKeepMaximumThumbInsideControl() {
        let viewWidth: CGFloat = 220
        let horizontalPadding: CGFloat = 5
        let trackWidth = viewWidth - horizontalPadding * 2

        let rawBounds = SumiOpacityWaveMetrics.lineBounds(
            trackWidth: trackWidth,
            horizontalPadding: horizontalPadding
        )
        XCTAssertGreaterThan(rawBounds.upperBound, viewWidth)

        let fittedBounds = SumiOpacityWaveMetrics.interactiveLineBounds(
            trackWidth: trackWidth,
            horizontalPadding: horizontalPadding,
            viewWidth: viewWidth
        )
        let maxThumbHalfWidth = SumiOpacityWaveMetrics.thumbSize(for: 1).width / 2

        XCTAssertLessThanOrEqual(
            fittedBounds.upperBound + maxThumbHalfWidth,
            viewWidth - 0.9999
        )
        XCTAssertGreaterThanOrEqual(
            fittedBounds.lowerBound - maxThumbHalfWidth,
            0.9999
        )
    }

    func testProgressCanMoveBackFromMaximumWithoutRequiringRetap() {
        let viewWidth: CGFloat = 220
        let horizontalPadding: CGFloat = 5
        let trackWidth = viewWidth - horizontalPadding * 2
        let lineBounds = SumiOpacityWaveMetrics.interactiveLineBounds(
            trackWidth: trackWidth,
            horizontalPadding: horizontalPadding,
            viewWidth: viewWidth
        )

        XCTAssertEqual(
            SumiOpacityWaveMetrics.progress(for: lineBounds.upperBound, in: lineBounds),
            1,
            accuracy: 0.0001
        )
        XCTAssertLessThan(
            SumiOpacityWaveMetrics.progress(for: lineBounds.upperBound - 8, in: lineBounds),
            1
        )
    }

    func testInteractiveLineBoundsPreserveTravelWidthWhenOnlyShiftIsNeeded() {
        let viewWidth: CGFloat = 220
        let horizontalPadding: CGFloat = 5
        let trackWidth = viewWidth - horizontalPadding * 2

        let rawBounds = SumiOpacityWaveMetrics.lineBounds(
            trackWidth: trackWidth,
            horizontalPadding: horizontalPadding
        )
        let fittedBounds = SumiOpacityWaveMetrics.interactiveLineBounds(
            trackWidth: trackWidth,
            horizontalPadding: horizontalPadding,
            viewWidth: viewWidth
        )

        XCTAssertEqual(
            rawBounds.upperBound - rawBounds.lowerBound,
            fittedBounds.upperBound - fittedBounds.lowerBound,
            accuracy: 0.0001
        )
    }
}
