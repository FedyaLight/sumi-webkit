import Foundation
@testable import Sumi
import XCTest

@MainActor
extension SpaceSidebarTransitionStateTests {
    func testSwipeGestureBeginCreatesInteractiveSessionWithoutDestination() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        XCTAssertEqual(state.sourceSpaceId, ids[0])
        XCTAssertNil(state.destinationSpaceId)
        XCTAssertEqual(state.phase, .interactive)
        XCTAssertEqual(state.trigger, .swipe)
        XCTAssertFalse(state.isCommitArmed)
        XCTAssertEqual(state.progress, 0, accuracy: 0.0001)
    }

    func testSwipeUpdateLatchesDestinationAndPreservesProgress() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        state.updateSwipeGesture(
            progress: 0.24,
            latchedDirection: nil,
            orderedSpaceIds: ids
        )

        XCTAssertEqual(state.progress, 0.24, accuracy: 0.0001)
        XCTAssertNil(state.destinationSpaceId)
        XCTAssertEqual(state.direction, 0)

        state.updateSwipeGesture(
            progress: 0.32,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertEqual(state.progress, 0.32, accuracy: 0.0001)
        XCTAssertEqual(state.direction, 1)
        XCTAssertEqual(state.destinationSpaceId, ids[1])
        XCTAssertTrue(state.isCommitArmed)
    }

    func testSwipeBelowThresholdCancelsCleanly() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        state.updateSwipeGesture(
            progress: 0.24,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertFalse(state.shouldCommitSwipeOnEnd)
        XCTAssertNil(state.finishTransition(commit: false))
        XCTAssertFalse(state.hasDestination)
    }

    func testSwipeAboveThresholdCommitsDestination() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginSwipeGesture(
                from: ids[0],
                orderedSpaceIds: ids
            )
        )

        state.updateSwipeGesture(
            progress: 0.74,
            latchedDirection: 1,
            orderedSpaceIds: ids
        )

        XCTAssertTrue(state.shouldCommitSwipeOnEnd)
        XCTAssertEqual(state.finishTransition(commit: true), ids[1])
        XCTAssertFalse(state.hasDestination)
    }

    func testSpaceListMutationResetsInvalidTransitionSafely() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginClick(
                from: ids[0],
                to: ids[2],
                orderedSpaceIds: ids
            )
        )

        state.syncSpaces(
            orderedSpaceIds: [ids[0], ids[1]],
            committedSpaceId: ids[0]
        )

        XCTAssertFalse(state.hasDestination)
        XCTAssertNil(state.visualSelectedSpaceId)
    }

    func testNormalizedProgressPreservesReleaseTailAtHighVelocity() {
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 0, width: 100),
            0,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 40, width: 100),
            0.4,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 82, width: 100),
            0.82,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 91, width: 100),
            0.87,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 100, width: 100),
            0.92,
            accuracy: 0.0001
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.normalizedProgress(distance: 180, width: 100),
            0.92,
            accuracy: 0.0001
        )
    }

    func testDirectionLatchKeepsFirstDirection() {
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.latchedDirection(current: nil, rawDeltaX: -1.2),
            1
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.latchedDirection(current: 1, rawDeltaX: 4),
            1
        )
        XCTAssertEqual(
            SpaceSidebarSwipePhysics.latchedDirection(current: -1, rawDeltaX: -4),
            -1
        )
    }

    func testSwipeTrackerHorizontalLockConsumesAndEmitsExpectedEvents() {
        var tracker = SpaceSwipeGestureTracker()

        let began = tracker.process(
            .init(phase: .began, scrollingDeltaX: -0.4, scrollingDeltaY: 0.1),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(began.handling, .consume)
        XCTAssertEqual(began.emittedEvents, [.init(phase: .began, direction: nil, progress: 0)])

        let changed = tracker.process(
            .init(phase: .changed, scrollingDeltaX: -3.0, scrollingDeltaY: 0.2),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(changed.handling, .consume)
        XCTAssertEqual(changed.emittedEvents.count, 1)
        XCTAssertEqual(changed.emittedEvents[0].phase, .changed)
        XCTAssertEqual(changed.emittedEvents[0].direction, 1)
        XCTAssertGreaterThan(changed.emittedEvents[0].progress, 0.01)

        let ended = tracker.process(
            .init(phase: .ended),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(ended.handling, .consume)
        XCTAssertEqual(ended.emittedEvents.count, 1)
        XCTAssertEqual(ended.emittedEvents[0].phase, .ended)
        XCTAssertEqual(ended.emittedEvents[0].direction, 1)
        XCTAssertGreaterThan(ended.emittedEvents[0].progress, 0.01)
    }

    func testSwipeTrackerPhaseLessInputTriggersOnceAndDrainsInertialTail() {
        var tracker = SpaceSwipeGestureTracker()

        let belowThreshold = tracker.process(
            .init(scrollingDeltaX: -4, scrollingDeltaY: 0, timestamp: 1),
            width: 200,
            isEnabled: true
        )
        XCTAssertTrue(belowThreshold.emittedEvents.isEmpty)

        let triggered = tracker.process(
            .init(scrollingDeltaX: -70, scrollingDeltaY: 0, timestamp: 1.01),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(triggered.emittedEvents.last?.phase, .discrete)
        XCTAssertEqual(triggered.emittedEvents.last?.direction, 1)
        XCTAssertTrue(tracker.ownsScrollSequence)

        let inertialTail = tracker.process(
            .init(scrollingDeltaX: -100, scrollingDeltaY: 0, timestamp: 1.02),
            width: 200,
            isEnabled: false
        )
        XCTAssertEqual(inertialTail.handling, .consume)
        XCTAssertTrue(inertialTail.emittedEvents.isEmpty)

        _ = tracker.process(
            .init(scrollingDeltaX: 4, scrollingDeltaY: 0, timestamp: 1.30),
            width: 200,
            isEnabled: true
        )
        let nextGesture = tracker.process(
            .init(scrollingDeltaX: 70, scrollingDeltaY: 0, timestamp: 1.31),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(nextGesture.emittedEvents.last?.phase, .discrete)
        XCTAssertEqual(nextGesture.emittedEvents.last?.direction, -1)
    }

    func testSwipeTrackerDoesNotOwnANewPhaseLessGestureWhenDisabled() {
        var tracker = SpaceSwipeGestureTracker()

        _ = tracker.process(
            .init(scrollingDeltaX: -4, timestamp: 1),
            width: 200,
            isEnabled: true
        )
        _ = tracker.process(
            .init(scrollingDeltaX: -70, timestamp: 1.01),
            width: 200,
            isEnabled: true
        )
        XCTAssertTrue(tracker.ownsScrollSequence)

        let newGesture = tracker.process(
            .init(scrollingDeltaX: 4, timestamp: 1.30),
            width: 200,
            isEnabled: false
        )

        XCTAssertEqual(newGesture.handling, .forwardToUnderlying)
        XCTAssertTrue(newGesture.emittedEvents.isEmpty)
        XCTAssertFalse(tracker.ownsScrollSequence)
    }

    func testSwipeTrackerVerticalLockCancelsAndForwardsToUnderlying() {
        var tracker = SpaceSwipeGestureTracker()

        _ = tracker.process(
            .init(phase: .began, scrollingDeltaX: 0.2, scrollingDeltaY: 0.2),
            width: 200,
            isEnabled: true
        )

        let changed = tracker.process(
            .init(phase: .changed, scrollingDeltaX: 0.4, scrollingDeltaY: 3.2),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(changed.handling, .forwardToUnderlying)
        XCTAssertEqual(changed.emittedEvents, [.init(phase: .cancelled, direction: nil, progress: 0)])
        XCTAssertEqual(tracker.axisLock, .vertical)

        let ended = tracker.process(
            .init(phase: .ended),
            width: 200,
            isEnabled: true
        )
        XCTAssertEqual(ended.handling, .forwardToUnderlying)
        XCTAssertTrue(ended.emittedEvents.isEmpty)
        XCTAssertEqual(tracker.axisLock, .unresolved)
    }

    func testSwipeTrackerDisabledDoesNotStartGesture() {
        var tracker = SpaceSwipeGestureTracker()

        let result = tracker.process(
            .init(phase: .began, scrollingDeltaX: -4, scrollingDeltaY: 0),
            width: 200,
            isEnabled: false
        )

        XCTAssertEqual(result.handling, .forwardToUnderlying)
        XCTAssertTrue(result.emittedEvents.isEmpty)
        XCTAssertEqual(tracker.axisLock, .unresolved)
        XCTAssertFalse(tracker.didSendBeginEvent)
    }

    func testSameSpaceClickIsNoOp() {
        let ids = [UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertFalse(
            state.beginClick(
                from: ids[0],
                to: ids[0],
                orderedSpaceIds: ids
            )
        )
        XCTAssertFalse(state.hasDestination)
    }

    func testClickDirectionMatchesSpaceOrder() {
        let ids = [UUID(), UUID(), UUID()]
        var state = SpaceSidebarTransitionState()

        XCTAssertTrue(
            state.beginClick(
                from: ids[0],
                to: ids[2],
                orderedSpaceIds: ids
            )
        )
        XCTAssertEqual(state.direction, 1)

        state.reset()

        XCTAssertTrue(
            state.beginClick(
                from: ids[2],
                to: ids[0],
                orderedSpaceIds: ids
            )
        )
        XCTAssertEqual(state.direction, -1)
    }

}
