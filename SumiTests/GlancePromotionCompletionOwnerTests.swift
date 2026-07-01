import XCTest

@testable import Sumi

@MainActor
final class GlancePromotionCompletionOwnerTests: XCTestCase {
    func testFallbackCompletesCurrentPromotion() async throws {
        let owner = GlancePromotionCompletionOwner()
        let sessionID = UUID()
        var fallbackSessionIDs: [UUID] = []
        let fallbackCompleted = expectation(description: "fallbackCompleted")

        owner.beginAwaitingAttachment(
            sessionID: sessionID,
            fallbackDelayNanoseconds: 1_000_000
        ) {
            fallbackSessionIDs.append(sessionID)
            fallbackCompleted.fulfill()
        }

        await fulfillment(of: [fallbackCompleted], timeout: 1)

        XCTAssertEqual(fallbackSessionIDs, [sessionID])
        XCTAssertFalse(owner.isAwaitingAttachment)
    }

    func testAttachmentCompletionCancelsFallback() async throws {
        let owner = GlancePromotionCompletionOwner()
        let sessionID = UUID()
        var fallbackCount = 0

        owner.beginAwaitingAttachment(
            sessionID: sessionID,
            fallbackDelayNanoseconds: 20_000_000
        ) {
            fallbackCount += 1
        }

        XCTAssertTrue(owner.completeAttachment(sessionID: sessionID))

        try await Task.sleep(nanoseconds: 40_000_000)

        XCTAssertEqual(fallbackCount, 0)
        XCTAssertFalse(owner.isAwaitingAttachment)
    }

    func testMismatchedCompletionDoesNotCancelFallback() async throws {
        let owner = GlancePromotionCompletionOwner()
        let sessionID = UUID()
        var fallbackCount = 0
        let fallbackCompleted = expectation(description: "fallbackCompleted")

        owner.beginAwaitingAttachment(
            sessionID: sessionID,
            fallbackDelayNanoseconds: 1_000_000
        ) {
            fallbackCount += 1
            fallbackCompleted.fulfill()
        }

        XCTAssertFalse(owner.completeAttachment(sessionID: UUID()))

        await fulfillment(of: [fallbackCompleted], timeout: 1)

        XCTAssertEqual(fallbackCount, 1)
        XCTAssertFalse(owner.isAwaitingAttachment)
    }

    func testNewPromotionInvalidatesEarlierFallback() async throws {
        let owner = GlancePromotionCompletionOwner()
        let firstSessionID = UUID()
        let secondSessionID = UUID()
        var fallbackSessionIDs: [UUID] = []

        owner.beginAwaitingAttachment(
            sessionID: firstSessionID,
            fallbackDelayNanoseconds: 1_000_000
        ) {
            fallbackSessionIDs.append(firstSessionID)
        }
        owner.beginAwaitingAttachment(
            sessionID: secondSessionID,
            fallbackDelayNanoseconds: 20_000_000
        ) {
            fallbackSessionIDs.append(secondSessionID)
        }

        try await Task.sleep(nanoseconds: 10_000_000)

        XCTAssertTrue(fallbackSessionIDs.isEmpty)
        XCTAssertTrue(owner.isAwaitingAttachment)
        XCTAssertTrue(owner.completeAttachment(sessionID: secondSessionID))
    }
}
