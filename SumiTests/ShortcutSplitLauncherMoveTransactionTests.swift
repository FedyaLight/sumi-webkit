import XCTest

@testable import Sumi

@MainActor
final class ShortcutSplitLauncherMoveTransactionTests: XCTestCase {
    func testRejectedBatchDoesNotCreateSidebarSideEffect() {
        let pin = makePin()
        var receivedIDs: [UUID] = []
        let batches = TestShortcutSplitLauncherMoveBatchPreparer(
            accepts: { _, _ in true },
            prepare: {
                receivedIDs = $0.map { $0.pin.id }
                return nil
            },
            prepareForComposedResidenceAggregate: { _ in
                XCTFail("Unexpected composed-residence preparation")
                return nil
            }
        )
        let transaction = ShortcutSplitLauncherMoveTransaction(
            batches: batches,
            windowMutations: BrowserWindowShortcutMutationOwner()
        )

        XCTAssertNil(transaction.stage([restoration(for: pin)]))
        XCTAssertEqual(receivedIDs, [pin.id])
    }

    func testPreparedBatchSettlesBeforeTerminalPublication() throws {
        let pin = makePin()
        var effects: [String] = []
        let batch = TestShortcutSplitLauncherMoveBatchParticipant(
            isCurrent: { true },
            rollback: {
                effects.append("rollback")
                return true
            },
            settle: { effects.append("settle") },
            publish: { effects.append("publish") }
        )
        let transaction = ShortcutSplitLauncherMoveTransaction(
            batches: TestShortcutSplitLauncherMoveBatchPreparer(
                accepts: { _, _ in true },
                prepare: { _ in batch },
                prepareForComposedResidenceAggregate: { _ in
                    XCTFail("Unexpected composed-residence preparation")
                    return nil
                }
            ),
            windowMutations: BrowserWindowShortcutMutationOwner()
        )

        let sideEffect = try XCTUnwrap(
            transaction.stage([restoration(for: pin)])
        )
        XCTAssertTrue(sideEffect.settleModel())
        XCTAssertEqual(effects, ["settle"])

        sideEffect.commit()
        XCTAssertEqual(effects, ["settle", "publish"])
    }

    func testComposedResidenceStageUsesItsDedicatedBatchPreparation() {
        let pin = makePin()
        var ordinaryPreparationCount = 0
        var composedPreparationCount = 0
        let batch = TestShortcutSplitLauncherMoveBatchParticipant(
            isCurrent: { true },
            rollback: { true },
            settle: {},
            publish: {}
        )
        let transaction = ShortcutSplitLauncherMoveTransaction(
            batches: TestShortcutSplitLauncherMoveBatchPreparer(
                accepts: { _, _ in true },
                prepare: { _ in
                    ordinaryPreparationCount += 1
                    return nil
                },
                prepareForComposedResidenceAggregate: { _ in
                    composedPreparationCount += 1
                    return batch
                }
            ),
            windowMutations: BrowserWindowShortcutMutationOwner()
        )

        XCTAssertNotNil(
            transaction.stageForComposedResidenceAggregate([
                restoration(for: pin),
            ])
        )
        XCTAssertEqual(ordinaryPreparationCount, 0)
        XCTAssertEqual(composedPreparationCount, 1)
    }

    private func makePin() -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: UUID(),
            index: 0,
            launchURL: URL(string: "https://launcher.example")!,
            title: "Launcher"
        )
    }

    private func restoration(
        for pin: ShortcutPin
    ) -> PreparedShortcutSplitLauncherRestoration {
        PreparedShortcutSplitLauncherRestoration(
            pin: pin,
            destination: ShortcutSplitLauncherDestination(
                role: pin.role,
                profileId: pin.profileId,
                spaceId: pin.spaceId,
                folderId: pin.folderId,
                index: pin.index
            )
        )
    }
}
