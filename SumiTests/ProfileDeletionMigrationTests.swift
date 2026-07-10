import XCTest

@testable import Sumi

@MainActor
final class ProfileDeletionMigrationTests: XCTestCase {
    func testSettlementWaitsForEveryTransition() async {
        let deletedProfileID = UUID()
        let fallbackProfileID = UUID()
        var callbacks: [ProfileTransitionService.Settlement] = []
        var finishedOutcome: ProfileDeletionMigrationOutcome?
        let coordinator = makeCoordinator()

        let task = Task { @MainActor in
            let outcome = await coordinator.settle(
                .init(
                    deletedProfileID: deletedProfileID,
                    fallbackProfileID: fallbackProfileID,
                    operations: [
                        deferredOperation(id: .space(UUID())) {
                            callbacks.append($0)
                        },
                        deferredOperation(id: .tab(UUID())) {
                            callbacks.append($0)
                        },
                    ]
                )
            )
            finishedOutcome = outcome
            return outcome
        }
        await Task.yield()

        XCTAssertEqual(callbacks.count, 2)
        XCTAssertNil(finishedOutcome)
        callbacks[0](.committed)
        await Task.yield()
        XCTAssertNil(finishedOutcome)

        callbacks[1](.committed)
        let outcome = await task.value
        XCTAssertEqual(outcome, .committed)
        XCTAssertEqual(finishedOutcome, .committed)
    }

    func testRejectedTransitionRejectsWholeSettlement() async {
        let coordinator = makeCoordinator()
        let outcome = await coordinator.settle(
            .init(
                deletedProfileID: UUID(),
                fallbackProfileID: UUID(),
                operations: [
                    .init(
                        id: .tab(UUID()),
                        start: { callback in
                            callback(.rejected(.failed))
                            return .failed
                        },
                        cancelPending: {}
                    ),
                ]
            )
        )
        XCTAssertEqual(outcome, .rejected)
    }

    func testTimeoutAbortsTransitionsAndCancelsPendingIntent() async {
        let deletedProfileID = UUID()
        let fallbackProfileID = UUID()
        var abortedProfileIDs: Set<UUID> = []
        var cancelCount = 0
        let coordinator = makeCoordinator(
            waitForTimeout: {},
            abortTransitions: { profileIDs in
                abortedProfileIDs = profileIDs
                return 1
            }
        )

        let outcome = await coordinator.settle(
            .init(
                deletedProfileID: deletedProfileID,
                fallbackProfileID: fallbackProfileID,
                operations: [
                    .init(
                        id: .space(UUID()),
                        start: { _ in .deferred },
                        cancelPending: { cancelCount += 1 }
                    ),
                ]
            )
        )

        XCTAssertEqual(outcome, .timedOut)
        XCTAssertEqual(
            abortedProfileIDs,
            [deletedProfileID, fallbackProfileID]
        )
        XCTAssertEqual(cancelCount, 1)
    }

    private func deferredOperation(
        id: ProfileDeletionOperationID,
        capture: @escaping (
            @escaping ProfileTransitionService.Settlement
        ) -> Void
    ) -> ProfileDeletionOperation {
        .init(
            id: id,
            start: { callback in
                capture(callback)
                return .deferred
            },
            cancelPending: {}
        )
    }

    private func makeCoordinator(
        waitForTimeout: @escaping @MainActor () async -> Void = {
            do {
                try await Task.sleep(for: .seconds(60))
            } catch {
                return
            }
        },
        abortTransitions: @escaping (Set<UUID>) -> Int = { _ in 0 }
    ) -> ProfileDeletionSettlementCoordinator {
        ProfileDeletionSettlementCoordinator(
            waitForTimeout: waitForTimeout,
            abortTransitions: abortTransitions
        )
    }
}
