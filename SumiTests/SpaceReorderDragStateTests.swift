import CoreGraphics
import SwiftUI
import XCTest
@testable import Sumi

final class SpaceReorderDragStateTests: XCTestCase {
    private let metrics = SpaceStripMetrics.resolve(for: .regular)

    func testLiveReorderMovesDraggedSpaceAcrossSlotsToTheRight() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let geometry = makeGeometry(itemCount: 3)
        var state = SpaceReorderDragState()

        var result = state.update(
            spaceId: first,
            location: CGPoint(x: 16, y: 16),
            orderedSpaceIds: [first, second, third],
            geometry: geometry
        )
        XCTAssertFalse(result.didBeginDrag)
        XCTAssertFalse(result.didReorder)
        XCTAssertNil(state.visualOrder)

        result = state.update(
            spaceId: first,
            location: CGPoint(x: 61, y: 16),
            orderedSpaceIds: [first, second, third],
            geometry: geometry
        )
        XCTAssertTrue(result.didBeginDrag)
        XCTAssertTrue(result.didReorder)
        XCTAssertEqual(state.visualOrder, [second, first, third])

        result = state.update(
            spaceId: first,
            location: CGPoint(x: 101, y: 16),
            orderedSpaceIds: [second, first, third],
            geometry: geometry
        )
        XCTAssertFalse(result.didBeginDrag)
        XCTAssertTrue(result.didReorder)
        XCTAssertEqual(state.visualOrder, [second, third, first])
        XCTAssertEqual(state.finish(), SpaceReorderDrop(spaceId: first, targetIndex: 2))
    }

    func testLiveReorderMovesDraggedSpaceAcrossSlotsToTheLeft() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let geometry = makeGeometry(itemCount: 3)
        var state = SpaceReorderDragState()

        _ = state.update(
            spaceId: third,
            location: CGPoint(x: 96, y: 16),
            orderedSpaceIds: [first, second, third],
            geometry: geometry
        )
        var result = state.update(
            spaceId: third,
            location: CGPoint(x: 51, y: 16),
            orderedSpaceIds: [first, second, third],
            geometry: geometry
        )
        XCTAssertTrue(result.didBeginDrag)
        XCTAssertEqual(state.visualOrder, [first, third, second])

        result = state.update(
            spaceId: third,
            location: CGPoint(x: 11, y: 16),
            orderedSpaceIds: [first, third, second],
            geometry: geometry
        )
        XCTAssertTrue(result.didReorder)
        XCTAssertEqual(state.visualOrder, [third, first, second])
        XCTAssertEqual(state.finish(), SpaceReorderDrop(spaceId: third, targetIndex: 0))
    }

    func testInsertionBoundaryUsesNeighborSlotCenters() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let geometry = makeGeometry(itemCount: 3)
        var state = SpaceReorderDragState()

        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 16, y: 16),
            orderedSpaceIds: [first, second, third],
            geometry: geometry
        )
        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 56, y: 16),
            orderedSpaceIds: [first, second, third],
            geometry: geometry
        )
        XCTAssertEqual(state.visualOrder, [first, second, third])

        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 56.1, y: 16),
            orderedSpaceIds: [first, second, third],
            geometry: geometry
        )
        XCTAssertEqual(state.visualOrder, [second, first, third])
    }

    func testDraggedOverlayFollowsCursorBeyondStripBounds() throws {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let geometry = makeGeometry(itemCount: 3)
        var state = SpaceReorderDragState()

        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 16, y: 16),
            orderedSpaceIds: [first, second, third],
            geometry: geometry
        )
        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 400, y: 16),
            orderedSpaceIds: [first, second, third],
            geometry: geometry
        )

        let overlayFrame = try XCTUnwrap(state.draggedOverlayFrame())
        XCTAssertEqual(overlayFrame.midX, 400, accuracy: 0.001)
        XCTAssertEqual(state.visualOrder, [second, third, first])
    }

    func testBelowThresholdDragDoesNotCreateDropOrSuppressClick() throws {
        let first = UUID()
        let second = UUID()
        let geometry = makeGeometry(itemCount: 2)
        var state = SpaceReorderDragState()

        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 16, y: 16),
            orderedSpaceIds: [first, second],
            geometry: geometry
        )
        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 19, y: 16),
            orderedSpaceIds: [first, second],
            geometry: geometry
        )

        let overlayFrame = try XCTUnwrap(state.draggedOverlayFrame())
        XCTAssertEqual(overlayFrame.midX, 19, accuracy: 0.001)
        XCTAssertNil(state.finish())
        XCTAssertFalse(state.consumeSuppressedClick(for: first))
    }

    func testFinishedDragSuppressesSyntheticClickOnce() {
        let first = UUID()
        let second = UUID()
        let geometry = makeGeometry(itemCount: 2)
        var state = SpaceReorderDragState()

        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 16, y: 16),
            orderedSpaceIds: [first, second],
            geometry: geometry
        )
        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 58, y: 16),
            orderedSpaceIds: [first, second],
            geometry: geometry
        )

        XCTAssertEqual(state.finish(), SpaceReorderDrop(spaceId: first, targetIndex: 1))
        XCTAssertTrue(state.consumeSuppressedClick(for: first))
        XCTAssertFalse(state.consumeSuppressedClick(for: first))
    }

    func testGeometryUsesControlSizeMetricsAndBoundedSpacing() {
        let small = SpaceStripMetrics.resolve(for: .small)
        let compactVisual = SpaceStripGeometry.make(itemCount: 3, availableWidth: 200, metrics: small)
        let normalVisual = SpaceStripGeometry.make(itemCount: 3, availableWidth: 200, metrics: small)

        XCTAssertEqual(small.slotSize, 28)
        XCTAssertEqual(compactVisual.slotFrames.map(\.width), [28, 28, 28])
        XCTAssertEqual(compactVisual, normalVisual)
        XCTAssertGreaterThanOrEqual(compactVisual.spacing, small.minSpacing)
        XCTAssertLessThanOrEqual(compactVisual.spacing, small.maxSpacing)
    }

    private func makeGeometry(itemCount: Int) -> SpaceStripGeometry {
        SpaceStripGeometry.make(
            itemCount: itemCount,
            availableWidth: CGFloat(itemCount * 40 - 8),
            metrics: metrics
        )
    }
}
