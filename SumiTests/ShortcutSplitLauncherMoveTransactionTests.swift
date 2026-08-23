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
