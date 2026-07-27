import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class ShortcutSplitLauncherMoveTransactionTests: XCTestCase {
    func testRejectedBatchDoesNotCreateSidebarSideEffect() throws {
        let folderOpenState = try makeFolderOpenState()
        let pin = makePin()
        var receivedIDs: [UUID] = []
        let batches = TestShortcutSplitLauncherMoveBatchPreparer(
            accepts: { _, _ in true },
            prepare: {
                receivedIDs = $0.map { $0.pin.id }
                return nil
            },
            prepareForComposedResidenceAggregate: { _, _ in
                XCTFail("Unexpected composed-residence preparation")
                return nil
            },
            prepareBindingContributionForComposedResidenceAggregate: { _ in
                XCTFail("Unexpected composed binding contribution")
                return nil
            },
            preflightBindingContribution: { _ in
                XCTFail("Unexpected binding preflight")
                return nil
            },
            prepareBindingContributionPlan: { _, _ in
                XCTFail("Unexpected insertion-plan contribution")
                return nil
            }
        )
        let transaction = ShortcutSplitLauncherMoveTransaction(
            batches: batches,
            windowMutations: BrowserWindowShortcutMutationOwner(),
            folderOpenState: folderOpenState
        )

        XCTAssertNil(transaction.stage([preparedMove(for: pin)]))
        XCTAssertEqual(receivedIDs, [pin.id])
    }

    func testPreparedBatchSettlesBeforeTerminalPublication() throws {
        let folderOpenState = try makeFolderOpenState()
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
                prepareForComposedResidenceAggregate: { _, _ in
                    XCTFail("Unexpected composed-residence preparation")
                    return nil
                },
                prepareBindingContributionForComposedResidenceAggregate: { _ in
                    XCTFail("Unexpected composed binding contribution")
                    return nil
                },
                preflightBindingContribution: { _ in
                    XCTFail("Unexpected binding preflight")
                    return nil
                },
                prepareBindingContributionPlan: { _, _ in
                    XCTFail("Unexpected insertion-plan contribution")
                    return nil
                }
            ),
            windowMutations: BrowserWindowShortcutMutationOwner(),
            folderOpenState: folderOpenState
        )

        let sideEffect = try XCTUnwrap(
            transaction.stage([preparedMove(for: pin)])
        )
        XCTAssertTrue(sideEffect.settleModel())
        XCTAssertEqual(effects, ["settle"])

        sideEffect.commit()
        XCTAssertEqual(effects, ["settle", "publish"])
    }

    func testComposedResidenceStageUsesItsDedicatedBatchPreparation() throws {
        let folderOpenState = try makeFolderOpenState()
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
                prepareForComposedResidenceAggregate: { _, _ in
                    composedPreparationCount += 1
                    return batch
                },
                prepareBindingContributionForComposedResidenceAggregate: { _ in
                    XCTFail("Unexpected composed binding contribution")
                    return nil
                },
                preflightBindingContribution: { _ in
                    XCTFail("Unexpected binding preflight")
                    return nil
                },
                prepareBindingContributionPlan: { _, _ in
                    XCTFail("Unexpected insertion-plan contribution")
                    return nil
                }
            ),
            windowMutations: BrowserWindowShortcutMutationOwner(),
            folderOpenState: folderOpenState
        )

        XCTAssertNotNil(
            transaction.stageForComposedResidenceAggregate([
                preparedMove(for: pin),
            ], bindingMode: .preservingLiveBindings)
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

    private func makeFolderOpenState() throws -> TabFolderOpenStateService {
        let container = try makeInMemoryStartupDatabase()
        let manager = TabManager(
            database: container,
            webViewSessions: WebViewSessionRepository(),
            profileReferenceAdmission: try ProfileReferenceAdmissionLedger(
                database: container
            ),
            loadPersistedState: false
        )
        return TabFolderOpenStateService(
            folders: manager.stateStore.folders,
            structuralLookup: TabStructuralLookupCoordinator(
                eventBus: manager.tabStructureEventBus,
                stateStore: manager.stateStore
            ),
            persistence: manager.structuralPersistence
        )
    }

    private func preparedMove(
        for pin: ShortcutPin
    ) -> PreparedShortcutSplitLauncherMove {
        PreparedShortcutSplitLauncherMove(
            pin: pin,
            destination: ShortcutSplitLauncherDestination(
                role: pin.role,
                profileId: pin.profileId,
                spaceId: pin.spaceId,
                folderId: pin.folderId,
                index: pin.index,
                opensFolder: false
            )
        )
    }
}
