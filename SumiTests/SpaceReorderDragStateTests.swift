import CoreGraphics
import XCTest
@testable import Sumi

final class SpaceReorderDragStateTests: XCTestCase {
    func testLiveReorderMovesDraggedSpaceAcrossNeighborMidpoints() throws {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var state = SpaceReorderDragState()
        state.updateItemFrames(frames(for: [first, second, third]))

        var result = state.update(spaceId: first, location: CGPoint(x: 17, y: 16), orderedSpaceIds: [first, second, third])
        XCTAssertFalse(result.didBeginDrag)
        XCTAssertFalse(result.didReorder)
        XCTAssertNil(state.visualOrder)

        result = state.update(spaceId: first, location: CGPoint(x: 61, y: 16), orderedSpaceIds: [first, second, third])
        XCTAssertTrue(result.didBeginDrag)
        XCTAssertTrue(result.didReorder)
        XCTAssertEqual(state.visualOrder, [second, first, third])

        state.updateItemFrames(frames(for: [second, first, third]))
        let overlayFrameAfterFirstReorder = try XCTUnwrap(state.draggedOverlayFrame())
        XCTAssertEqual(overlayFrameAfterFirstReorder.midX, 60, accuracy: 0.001)

        result = state.update(spaceId: first, location: CGPoint(x: 101, y: 16), orderedSpaceIds: [second, first, third])
        XCTAssertFalse(result.didBeginDrag)
        XCTAssertTrue(result.didReorder)
        XCTAssertEqual(state.visualOrder, [second, third, first])

        XCTAssertEqual(state.finish(), SpaceReorderDrop(spaceId: first, targetIndex: 2))
        XCTAssertNil(state.visualOrder)
        XCTAssertFalse(state.isDragging)
    }

    func testLiveReorderMovesDraggedSpaceLeftAcrossNeighborMidpoints() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var state = SpaceReorderDragState()
        state.updateItemFrames(frames(for: [first, second, third]))

        var result = state.update(spaceId: third, location: CGPoint(x: 96, y: 16), orderedSpaceIds: [first, second, third])
        XCTAssertFalse(result.didBeginDrag)
        XCTAssertFalse(result.didReorder)

        result = state.update(spaceId: third, location: CGPoint(x: 51, y: 16), orderedSpaceIds: [first, second, third])
        XCTAssertTrue(result.didBeginDrag)
        XCTAssertTrue(result.didReorder)
        XCTAssertEqual(state.visualOrder, [first, third, second])

        state.updateItemFrames(frames(for: [first, third, second]))
        result = state.update(spaceId: third, location: CGPoint(x: 11, y: 16), orderedSpaceIds: [first, third, second])
        XCTAssertFalse(result.didBeginDrag)
        XCTAssertTrue(result.didReorder)
        XCTAssertEqual(state.visualOrder, [third, first, second])
        XCTAssertEqual(state.finish(), SpaceReorderDrop(spaceId: third, targetIndex: 0))
    }

    func testDraggedSpaceOverlayFollowsCursorBeyondSpacesLineBounds() throws {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        var state = SpaceReorderDragState()
        state.updateItemFrames(frames(for: [first, second, third]))

        _ = state.update(spaceId: first, location: CGPoint(x: 16, y: 16), orderedSpaceIds: [first, second, third])
        _ = state.update(spaceId: first, location: CGPoint(x: 400, y: 16), orderedSpaceIds: [first, second, third])
        XCTAssertEqual(state.visualOrder, [second, third, first])

        state.updateItemFrames(frames(for: [second, third, first]))
        let overlayFrameBeyondBounds = try XCTUnwrap(state.draggedOverlayFrame())
        XCTAssertEqual(overlayFrameBeyondBounds.midX, 400, accuracy: 0.001)
    }

    func testBelowThresholdDragTracksCursorWithoutDroppingOrSuppressingClick() throws {
        let first = UUID()
        let second = UUID()
        var state = SpaceReorderDragState()
        state.updateItemFrames(frames(for: [first, second]))

        var result = state.update(spaceId: first, location: CGPoint(x: 16, y: 16), orderedSpaceIds: [first, second])
        XCTAssertFalse(result.didBeginDrag)
        XCTAssertFalse(result.didReorder)

        result = state.update(spaceId: first, location: CGPoint(x: 19, y: 16), orderedSpaceIds: [first, second])
        XCTAssertFalse(result.didBeginDrag)
        XCTAssertFalse(result.didReorder)
        let overlayFrameBelowThreshold = try XCTUnwrap(state.draggedOverlayFrame())
        XCTAssertEqual(overlayFrameBelowThreshold.midX, 19, accuracy: 0.001)

        XCTAssertNil(state.finish())
        XCTAssertFalse(state.consumeSuppressedClick(for: first))
    }

    func testFinishedDragSuppressesSyntheticClickOnce() {
        let first = UUID()
        let second = UUID()
        var state = SpaceReorderDragState()
        state.updateItemFrames(frames(for: [first, second]))

        _ = state.update(spaceId: first, location: CGPoint(x: 16, y: 16), orderedSpaceIds: [first, second])
        _ = state.update(spaceId: first, location: CGPoint(x: 58, y: 16), orderedSpaceIds: [first, second])

        XCTAssertEqual(state.finish(), SpaceReorderDrop(spaceId: first, targetIndex: 1))
        XCTAssertTrue(state.consumeSuppressedClick(for: first))
        XCTAssertFalse(state.consumeSuppressedClick(for: first))
    }

    private func frames(for ids: [UUID]) -> [UUID: CGRect] {
        Dictionary(uniqueKeysWithValues: ids.enumerated().map { index, id in
            (id, CGRect(x: CGFloat(index) * 40, y: 0, width: 32, height: 32))
        })
    }
}
