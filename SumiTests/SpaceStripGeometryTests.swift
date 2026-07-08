import CoreGraphics
@testable import Sumi
import SwiftUI
import XCTest

/// Geometry + scroll-policy behavior of the sidebar spaces strip: full-size
/// slots while they fit, shrink to the minimum, then compact dots with
/// Zen-style "nearest + margin" scrolling.
final class SpaceStripGeometryTests: XCTestCase {
    private let metrics = SpaceStripMetrics.resolve(for: .regular)

    // MARK: - Stage 1: full-size slots

    func testFewItemsKeepFullSlotSizeAndCenteredLayout() {
        let geometry = SpaceStripGeometry.make(itemCount: 3, availableWidth: 200, metrics: metrics)

        XCTAssertEqual(geometry.displayMode, .regular)
        XCTAssertFalse(geometry.isScrollable)
        XCTAssertEqual(geometry.slotWidth, metrics.slotSize)
        XCTAssertEqual(geometry.slotFrames.map(\.width), [32, 32, 32])
        XCTAssertEqual(geometry.contentWidth, 200)

        // Centered: symmetric margins around the slots extent (3·32 + 2·8).
        let extent = geometry.slotFrames[2].maxX - geometry.slotFrames[0].minX
        XCTAssertEqual(geometry.slotFrames[0].minX, (200 - extent) / 2, accuracy: 0.001)
    }

    func testSpacingIsClampedToMaxSpacing() {
        let geometry = SpaceStripGeometry.make(itemCount: 2, availableWidth: 400, metrics: metrics)
        let gap = geometry.slotFrames[1].minX - geometry.slotFrames[0].maxX
        XCTAssertEqual(gap, metrics.maxSpacing)
    }

    func testSingleItemIsCentered() {
        let geometry = SpaceStripGeometry.make(itemCount: 1, availableWidth: 100, metrics: metrics)
        XCTAssertEqual(geometry.slotFrames[0].midX, 50, accuracy: 0.001)
        XCTAssertFalse(geometry.isScrollable)
    }

    // MARK: - Stage 2: shrinking

    func testSlotsShrinkWhenFullSizeNoLongerFits() {
        // 6 full slots need 6·32 + 5·1 = 197; give less so slots must shrink.
        let geometry = SpaceStripGeometry.make(itemCount: 6, availableWidth: 160, metrics: metrics)

        XCTAssertEqual(geometry.displayMode, .regular)
        XCTAssertFalse(geometry.isScrollable)
        XCTAssertLessThan(geometry.slotWidth, metrics.slotSize)
        XCTAssertGreaterThanOrEqual(geometry.slotWidth, metrics.minSlotSize)
        // Shrunk slots fill the viewport edge-to-edge.
        XCTAssertEqual(geometry.slotFrames[0].minX, 0, accuracy: 0.001)
        XCTAssertEqual(geometry.slotFrames[5].maxX, 160, accuracy: 0.001)
    }

    // MARK: - Stage 3: compact dots + scrolling

    func testCompactDotsEngageWhenMinimumSlotsOverflow() {
        // 10 slots at minimum (16) need 10·16 + 9·1 = 169 > 120.
        let geometry = SpaceStripGeometry.make(itemCount: 10, availableWidth: 120, metrics: metrics)

        XCTAssertEqual(geometry.displayMode, .compactDots)
        XCTAssertTrue(geometry.isScrollable)
        XCTAssertEqual(geometry.slotWidth, metrics.minSlotSize)
        // Scrollable content is anchored at zero, no gaps between slots.
        XCTAssertEqual(geometry.slotFrames[0].minX, 0)
        XCTAssertEqual(geometry.slotFrames[1].minX, metrics.minSlotSize)
        XCTAssertEqual(geometry.contentWidth, 10 * metrics.minSlotSize)
    }

    func testUnmeasuredWidthFallsBackToFullSizeRegularLayout() {
        let geometry = SpaceStripGeometry.make(itemCount: 8, availableWidth: 0, metrics: metrics)
        XCTAssertEqual(geometry.displayMode, .regular)
        XCTAssertFalse(geometry.isScrollable)
        XCTAssertEqual(geometry.slotWidth, metrics.slotSize)
    }

    func testEmptyStrip() {
        let geometry = SpaceStripGeometry.make(itemCount: 0, availableWidth: 100, metrics: metrics)
        XCTAssertTrue(geometry.slotFrames.isEmpty)
        XCTAssertFalse(geometry.isScrollable)
        XCTAssertNil(geometry.frame(at: 0))
    }

    // MARK: - Scroll policy (Zen scrollIntoView "nearest" + scroll-margin)

    private func scrollableGeometry(itemCount: Int = 10, viewport: CGFloat = 120) -> SpaceStripGeometry {
        SpaceStripGeometry.make(itemCount: itemCount, availableWidth: viewport, metrics: metrics)
    }

    func testNoScrollWhenSlotAlreadyVisibleWithMargin() {
        let geometry = scrollableGeometry()
        // Slot 3 spans 48..64; visible in 0..120 with 20pt margin on each side.
        XCTAssertNil(
            SpaceStripScrollPolicy.targetOffset(
                toReveal: 3,
                geometry: geometry,
                currentOffset: 0,
                viewportWidth: 120,
                margin: metrics.scrollMargin
            )
        )
    }

    func testScrollForwardRevealsSlotPlusMargin() {
        let geometry = scrollableGeometry()
        // Slot 7 spans 112..128, beyond the 0..120 viewport.
        let target = SpaceStripScrollPolicy.targetOffset(
            toReveal: 7,
            geometry: geometry,
            currentOffset: 0,
            viewportWidth: 120,
            margin: metrics.scrollMargin
        )
        // maxX (128) + margin (20) − viewport (120) = 28.
        XCTAssertEqual(target, 28)
    }

    func testScrollBackwardRevealsSlotMinusMargin() {
        let geometry = scrollableGeometry()
        // Scrolled to the end (contentWidth 160 − viewport 120 = 40); slot 1
        // spans 16..32, hidden behind the leading edge.
        let target = SpaceStripScrollPolicy.targetOffset(
            toReveal: 1,
            geometry: geometry,
            currentOffset: 40,
            viewportWidth: 120,
            margin: metrics.scrollMargin
        )
        // minX (16) − margin (20) = −4, clamped to 0.
        XCTAssertEqual(target, 0)
    }

    func testScrollClampsToContentEnd() {
        let geometry = scrollableGeometry()
        let target = SpaceStripScrollPolicy.targetOffset(
            toReveal: 9,
            geometry: geometry,
            currentOffset: 0,
            viewportWidth: 120,
            margin: metrics.scrollMargin
        )
        // Last slot maxX (160) + margin − viewport = 60, clamped to maxOffset 40.
        XCTAssertEqual(target, 40)
    }

    func testStaleOffsetResetsWhenContentFits() {
        let geometry = SpaceStripGeometry.make(itemCount: 3, availableWidth: 200, metrics: metrics)
        let target = SpaceStripScrollPolicy.targetOffset(
            toReveal: 0,
            geometry: geometry,
            currentOffset: 30,
            viewportWidth: 200,
            margin: metrics.scrollMargin
        )
        XCTAssertEqual(target, 0)
    }

    func testNeighbourPeeksAfterSequentialForwardSwitches() {
        // The user story: on space N, switch to N+1 — the strip shifts by one
        // slot so the previous space stays visible as the neighbour.
        let geometry = scrollableGeometry()
        var offset: CGFloat = 0
        var shifts: [CGFloat] = []
        for index in 0..<10 {
            if let target = SpaceStripScrollPolicy.targetOffset(
                toReveal: index,
                geometry: geometry,
                currentOffset: offset,
                viewportWidth: 120,
                margin: metrics.scrollMargin
            ) {
                shifts.append(target - offset)
                offset = target
            }
        }
        XCTAssertEqual(offset, 40)
        // First shift brings the margin into view, the steady-state shift is
        // exactly one slot width, and the final shift clamps at content end.
        XCTAssertEqual(shifts, [12, metrics.minSlotSize, 12])
    }
}
