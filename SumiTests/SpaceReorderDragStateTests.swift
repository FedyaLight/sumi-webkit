import XCTest
@testable import Sumi

@MainActor
final class SpaceReorderDragStateTests: XCTestCase {
    func testDragAcrossSpaceProducesReorderDrop() {
        let first = UUID()
        let second = UUID()
        let third = UUID()
        let orderedIds = [first, second, third]
        var state = SpaceReorderDragState()

        state.updateItemFrames([
            first: CGRect(x: 0, y: 0, width: 32, height: 32),
            second: CGRect(x: 40, y: 0, width: 32, height: 32),
            third: CGRect(x: 80, y: 0, width: 32, height: 32),
        ])

        XCTAssertFalse(
            state.update(
                spaceId: first,
                location: CGPoint(x: 0, y: 16),
                orderedSpaceIds: orderedIds
            )
        )
        XCTAssertTrue(
            state.update(
                spaceId: first,
                location: CGPoint(x: 98, y: 16),
                orderedSpaceIds: orderedIds
            )
        )

        XCTAssertEqual(
            state.finish(orderedSpaceIds: orderedIds),
            SpaceReorderDrop(spaceId: first, targetIndex: 2)
        )
    }

    func testBelowThresholdDragDoesNotDropOrSuppressClick() {
        let first = UUID()
        let second = UUID()
        let orderedIds = [first, second]
        var state = SpaceReorderDragState()

        state.updateItemFrames([
            first: CGRect(x: 0, y: 0, width: 32, height: 32),
            second: CGRect(x: 40, y: 0, width: 32, height: 32),
        ])

        XCTAssertFalse(
            state.update(
                spaceId: first,
                location: CGPoint(x: 0, y: 16),
                orderedSpaceIds: orderedIds
            )
        )
        XCTAssertFalse(
            state.update(
                spaceId: first,
                location: CGPoint(x: 3, y: 16),
                orderedSpaceIds: orderedIds
            )
        )

        XCTAssertNil(state.finish(orderedSpaceIds: orderedIds))
        XCTAssertFalse(state.consumeSuppressedClick(for: first))
    }

    func testFinishedDragSuppressesSyntheticClickOnce() {
        let first = UUID()
        let second = UUID()
        let orderedIds = [first, second]
        var state = SpaceReorderDragState()

        state.updateItemFrames([
            first: CGRect(x: 0, y: 0, width: 32, height: 32),
            second: CGRect(x: 40, y: 0, width: 32, height: 32),
        ])

        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 0, y: 16),
            orderedSpaceIds: orderedIds
        )
        _ = state.update(
            spaceId: first,
            location: CGPoint(x: 58, y: 16),
            orderedSpaceIds: orderedIds
        )

        XCTAssertEqual(
            state.finish(orderedSpaceIds: orderedIds),
            SpaceReorderDrop(spaceId: first, targetIndex: 1)
        )
        XCTAssertTrue(state.consumeSuppressedClick(for: first))
        XCTAssertFalse(state.consumeSuppressedClick(for: first))
    }
}
