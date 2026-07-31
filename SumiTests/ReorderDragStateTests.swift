import CoreGraphics
@testable import Sumi
import SwiftUI
import XCTest

final class ReorderDragStateTests: XCTestCase {
    private let metrics = SpaceStripMetrics.resolve(for: .regular)

    // MARK: - Horizontal (spaces / pinned toolbar)

    func testLiveReorderMovesDraggedItemAcrossSlotsToTheRight() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let geometry = makeHorizontalGeometry(itemCount: 3)
        var state = ReorderDragState<UUID>()

        var result = state.update(
            id: first,
            location: CGPoint(x: 16, y: 16),
            orderedIDs: [first, second, third],
            geometry: geometry
        )
        XCTAssertFalse(result.didBeginDrag)
        XCTAssertFalse(result.didReorder)
        XCTAssertNil(state.visualOrder)

        result = state.update(
            id: first,
            location: CGPoint(x: 61, y: 16),
            orderedIDs: [first, second, third],
            geometry: geometry
        )
        XCTAssertTrue(result.didBeginDrag)
        XCTAssertTrue(result.didReorder)
        XCTAssertEqual(state.visualOrder, [second, first, third])

        result = state.update(
            id: first,
            location: CGPoint(x: 101, y: 16),
            orderedIDs: [second, first, third],
            geometry: geometry
        )
        XCTAssertFalse(result.didBeginDrag)
        XCTAssertTrue(result.didReorder)
        XCTAssertEqual(state.visualOrder, [second, third, first])
        XCTAssertEqual(state.finish(), ReorderMove(id: first, targetIndex: 2))
    }

    func testLiveReorderMovesDraggedItemAcrossSlotsToTheLeft() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let geometry = makeHorizontalGeometry(itemCount: 3)
        var state = ReorderDragState<UUID>()

        _ = state.update(
            id: third,
            location: CGPoint(x: 96, y: 16),
            orderedIDs: [first, second, third],
            geometry: geometry
        )
        let result = state.update(
            id: third,
            location: CGPoint(x: 51, y: 16),
            orderedIDs: [first, second, third],
            geometry: geometry
        )
        XCTAssertTrue(result.didBeginDrag)
        XCTAssertEqual(state.visualOrder, [first, third, second])

        _ = state.update(
            id: third,
            location: CGPoint(x: 11, y: 16),
            orderedIDs: [first, third, second],
            geometry: geometry
        )
        XCTAssertEqual(state.visualOrder, [third, first, second])
        XCTAssertEqual(state.finish(), ReorderMove(id: third, targetIndex: 0))
    }

    func testInsertionBoundaryUsesNeighborSlotCenters() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let geometry = makeHorizontalGeometry(itemCount: 3)
        var state = ReorderDragState<UUID>()

        _ = state.update(
            id: first,
            location: CGPoint(x: 16, y: 16),
            orderedIDs: [first, second, third],
            geometry: geometry
        )
        _ = state.update(
            id: first,
            location: CGPoint(x: 56, y: 16),
            orderedIDs: [first, second, third],
            geometry: geometry
        )
        XCTAssertEqual(state.visualOrder, [first, second, third])

        _ = state.update(
            id: first,
            location: CGPoint(x: 56.1, y: 16),
            orderedIDs: [first, second, third],
            geometry: geometry
        )
        XCTAssertEqual(state.visualOrder, [second, first, third])
    }

    func testDraggedOverlayFollowsCursorBeyondStripBounds() throws {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let geometry = makeHorizontalGeometry(itemCount: 3)
        var state = ReorderDragState<UUID>()

        _ = state.update(
            id: first,
            location: CGPoint(x: 16, y: 16),
            orderedIDs: [first, second, third],
            geometry: geometry
        )
        _ = state.update(
            id: first,
            location: CGPoint(x: 400, y: 16),
            orderedIDs: [first, second, third],
            geometry: geometry
        )

        let overlayFrame = try XCTUnwrap(state.draggedOverlayFrame())
        XCTAssertEqual(overlayFrame.midX, 400, accuracy: 0.001)
        XCTAssertEqual(state.visualOrder, [second, third, first])
    }

    func testBelowThresholdDragDoesNotCreateMoveOrSuppressClick() throws {
        let first = UUID()
        let second = UUID()
        let geometry = makeHorizontalGeometry(itemCount: 2)
        var state = ReorderDragState<UUID>()

        _ = state.update(
            id: first,
            location: CGPoint(x: 16, y: 16),
            orderedIDs: [first, second],
            geometry: geometry
        )
        _ = state.update(
            id: first,
            location: CGPoint(x: 19, y: 16),
            orderedIDs: [first, second],
            geometry: geometry
        )

        let overlayFrame = try XCTUnwrap(state.draggedOverlayFrame())
        XCTAssertEqual(overlayFrame.midX, 19, accuracy: 0.001)
        XCTAssertNil(state.finish())
        XCTAssertFalse(state.consumeSuppressedClick(for: first))
    }

    /// Gestures are built with `minimumDistance: 0`, so tracking begins on the
    /// first mouse-down sample. The slot must stay visible until the drag
    /// threshold is crossed: hiding it on press blanks the button on every
    /// plain click, and any AppKit view hosted inside it (the extension popup
    /// anchor) would report `alphaValue == 0` when the click resolves.
    func testPressBelowThresholdKeepsInlineItemVisible() {
        let first = UUID()
        let second = UUID()
        let geometry = makeHorizontalGeometry(itemCount: 2)
        var state = ReorderDragState<UUID>()

        _ = state.update(
            id: first,
            location: CGPoint(x: 16, y: 16),
            orderedIDs: [first, second],
            geometry: geometry
        )
        XCTAssertTrue(state.isTrackingDrag)
        XCTAssertFalse(state.isDragging)
        XCTAssertFalse(state.hidesInlineItem(first))

        _ = state.update(
            id: first,
            location: CGPoint(x: 19, y: 16),
            orderedIDs: [first, second],
            geometry: geometry
        )
        XCTAssertFalse(state.hidesInlineItem(first))

        // Past the threshold the inline slot yields to the floating overlay.
        _ = state.update(
            id: first,
            location: CGPoint(x: 40, y: 16),
            orderedIDs: [first, second],
            geometry: geometry
        )
        XCTAssertTrue(state.isDragging)
        XCTAssertTrue(state.hidesInlineItem(first))
        XCTAssertFalse(state.hidesInlineItem(second))
    }

    func testFinishedDragSuppressesSyntheticClickOnce() {
        let first = UUID()
        let second = UUID()
        let geometry = makeHorizontalGeometry(itemCount: 2)
        var state = ReorderDragState<UUID>()

        _ = state.update(
            id: first,
            location: CGPoint(x: 16, y: 16),
            orderedIDs: [first, second],
            geometry: geometry
        )
        _ = state.update(
            id: first,
            location: CGPoint(x: 58, y: 16),
            orderedIDs: [first, second],
            geometry: geometry
        )

        XCTAssertEqual(state.finish(), ReorderMove(id: first, targetIndex: 1))
        XCTAssertTrue(state.consumeSuppressedClick(for: first))
        XCTAssertFalse(state.consumeSuppressedClick(for: first))
    }

    // MARK: - Vertical (settings search engines)

    func testVerticalReorderMovesDraggedRowDown() {
        let rowStep: CGFloat = 49
        let rowHeight: CGFloat = 48
        let geometry = makeVerticalGeometry(itemCount: 3, rowStep: rowStep, rowHeight: rowHeight)
        var state = ReorderDragState<String>(threshold: 0)

        // Grab the top row at its center, then move down past the second row.
        _ = state.update(
            id: "a",
            location: CGPoint(x: 5, y: 24),
            orderedIDs: ["a", "b", "c"],
            geometry: geometry
        )
        _ = state.update(
            id: "a",
            location: CGPoint(x: 5, y: 24 + rowStep + 5),
            orderedIDs: ["a", "b", "c"],
            geometry: geometry
        )

        XCTAssertEqual(state.visualOrder, ["b", "a", "c"])
        XCTAssertEqual(state.draggedSourceIndex, 0)
        XCTAssertEqual(state.draggedProjectedIndex, 1)
        XCTAssertEqual(state.finish(), ReorderMove(id: "a", targetIndex: 1))
    }

    // MARK: - Grid (hub tiles)

    func testGridReorderUsesRowMajorInsertion() {
        // 2x2 grid: a b / c d
        let geometry = ReorderGeometry(
            axis: .grid,
            slotFrames: [
                CGRect(x: 0, y: 0, width: 40, height: 40),
                CGRect(x: 50, y: 0, width: 40, height: 40),
                CGRect(x: 0, y: 50, width: 40, height: 40),
                CGRect(x: 50, y: 50, width: 40, height: 40),
            ]
        )
        var state = ReorderDragState<String>()

        _ = state.update(
            id: "a",
            location: CGPoint(x: 20, y: 20),
            orderedIDs: ["a", "b", "c", "d"],
            geometry: geometry
        )
        _ = state.update(
            id: "a",
            location: CGPoint(x: 70, y: 70),
            orderedIDs: ["a", "b", "c", "d"],
            geometry: geometry
        )

        XCTAssertEqual(state.visualOrder, ["b", "c", "a", "d"])
        XCTAssertEqual(state.finish(), ReorderMove(id: "a", targetIndex: 2))
    }

    func testGeometryUsesControlSizeMetricsAndBoundedSpacing() {
        let small = SpaceStripMetrics.resolve(for: .small)
        let geometry = SpaceStripGeometry.make(itemCount: 3, availableWidth: 200, metrics: small)

        XCTAssertEqual(small.slotSize, 28)
        XCTAssertEqual(geometry.slotFrames.map(\.width), [28, 28, 28])
        let gaps = zip(geometry.slotFrames, geometry.slotFrames.dropFirst()).map {
            $1.minX - $0.maxX
        }
        XCTAssertTrue(gaps.allSatisfy { $0 >= small.minSpacing })
        XCTAssertTrue(gaps.allSatisfy { $0 <= small.maxSpacing })
    }

    // MARK: - Helpers

    private func makeHorizontalGeometry(itemCount: Int) -> ReorderGeometry {
        ReorderGeometry(
            axis: .horizontal,
            slotFrames: SpaceStripGeometry.make(
                itemCount: itemCount,
                availableWidth: CGFloat(itemCount * 40 - 8),
                metrics: metrics
            ).slotFrames
        )
    }

    private func makeVerticalGeometry(
        itemCount: Int,
        rowStep: CGFloat,
        rowHeight: CGFloat
    ) -> ReorderGeometry {
        ReorderGeometry(
            axis: .vertical,
            slotFrames: (0..<itemCount).map { index in
                CGRect(x: 0, y: CGFloat(index) * rowStep, width: 1, height: rowHeight)
            }
        )
    }
}
