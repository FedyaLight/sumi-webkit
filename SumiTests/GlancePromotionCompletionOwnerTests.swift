import XCTest

@testable import Sumi

@MainActor
final class GlancePromotionCompletionOwnerTests: XCTestCase {
    func testFallbackCompletesCurrentPromotion() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let owner = GlancePromotionCompletionOwner(
            delayedActions: delayedActions.scheduler
        )
        let sessionID = UUID()
        var fallbackSessionIDs: [UUID] = []

        owner.beginAwaitingAttachment(
            sessionID: sessionID
        ) {
            fallbackSessionIDs.append(sessionID)
        }

        XCTAssertEqual(delayedActions.scheduledDelays, [1])
        delayedActions.runAll()

        XCTAssertEqual(fallbackSessionIDs, [sessionID])
        XCTAssertFalse(owner.isAwaitingAttachment)
    }

    func testAttachmentCompletionCancelsFallback() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let owner = GlancePromotionCompletionOwner(
            delayedActions: delayedActions.scheduler
        )
        let sessionID = UUID()
        var fallbackCount = 0

        owner.beginAwaitingAttachment(
            sessionID: sessionID
        ) {
            fallbackCount += 1
        }

        XCTAssertTrue(owner.completeAttachment(sessionID: sessionID))
        XCTAssertEqual(delayedActions.pendingActionCount, 0)
        delayedActions.runAll()

        XCTAssertEqual(fallbackCount, 0)
        XCTAssertFalse(owner.isAwaitingAttachment)
    }

    func testMismatchedCompletionDoesNotCancelFallback() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let owner = GlancePromotionCompletionOwner(
            delayedActions: delayedActions.scheduler
        )
        let sessionID = UUID()
        var fallbackCount = 0

        owner.beginAwaitingAttachment(
            sessionID: sessionID
        ) {
            fallbackCount += 1
        }

        XCTAssertFalse(owner.completeAttachment(sessionID: UUID()))
        delayedActions.runAll()

        XCTAssertEqual(fallbackCount, 1)
        XCTAssertFalse(owner.isAwaitingAttachment)
    }

    func testDeinitCancelsPendingFallback() {
        let delayedActions = ManualMainActorDelayedActionScheduler()
        var owner: GlancePromotionCompletionOwner? = GlancePromotionCompletionOwner(
            delayedActions: delayedActions.scheduler
        )
        var fallbackCount = 0

        owner?.beginAwaitingAttachment(sessionID: UUID()) {
            fallbackCount += 1
        }

        XCTAssertEqual(delayedActions.pendingActionCount, 1)
        owner = nil
        XCTAssertEqual(delayedActions.pendingActionCount, 0)
        delayedActions.runAll()
        XCTAssertEqual(fallbackCount, 0)
    }

    func testNewPromotionInvalidatesEarlierFallbackEvenIfCancellationDoesNotStopIt() {
        var scheduledActions: [@MainActor () -> Void] = []
        let owner = GlancePromotionCompletionOwner(
            delayedActions: MainActorDelayedActionScheduler { _, action in
                scheduledActions.append(action)
                return { /* Deliberately preserve stale work. */ }
            }
        )
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        var fallbackSessionIDs: [UUID] = []

        owner.beginAwaitingAttachment(
            sessionID: firstSessionID
        ) {
            fallbackSessionIDs.append(firstSessionID)
        }
        owner.beginAwaitingAttachment(
            sessionID: secondSessionID
        ) {
            fallbackSessionIDs.append(secondSessionID)
        }

        XCTAssertEqual(scheduledActions.count, 2)
        scheduledActions[0]()

        XCTAssertTrue(fallbackSessionIDs.isEmpty)
        XCTAssertTrue(owner.isAwaitingAttachment)
        XCTAssertTrue(owner.completeAttachment(sessionID: secondSessionID))
        scheduledActions[1]()
        XCTAssertTrue(fallbackSessionIDs.isEmpty)
    }
}
