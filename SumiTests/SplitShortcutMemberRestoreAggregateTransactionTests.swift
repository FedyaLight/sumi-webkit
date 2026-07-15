import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class SplitShortcutMemberRestoreAggregateTransactionTests: XCTestCase {
    func testCancelAttemptsEveryPreparedParticipantAfterBindingFailure() throws {
        let binding = RestoreAggregateBinding(cancelResult: false)
        let harness = try makeHarness(binding: binding)

        XCTAssertFalse(harness.aggregate.cancelPrepared())

        XCTAssertEqual(binding.cancelCount, 1)
        XCTAssertFalse(harness.participants.cancelPrepared())
    }

    func testRollbackCompensationFailureIsNotClassifiedAsStale() throws {
        let binding = RestoreAggregateBinding(rollbackFails: true)
        let harness = try makeHarness(binding: binding)
        try harness.aggregate.stage()

        XCTAssertThrowsError(try harness.aggregate.rollback()) { error in
            guard case SplitShortcutMemberRestoreAggregateError
                .compensationFailed = error else {
                return XCTFail("Expected compensation failure, got \(error)")
            }
        }

        XCTAssertTrue(harness.aggregate.retainsModelAfterFailedStage())
        XCTAssertFalse(harness.aggregate.settleTerminalDrain())
        XCTAssertEqual(binding.terminalDrainCount, 0)
    }

    func testTerminalDrainRejectsStagedAggregate() throws {
        let binding = RestoreAggregateBinding()
        let harness = try makeHarness(binding: binding)
        try harness.aggregate.stage()

        XCTAssertFalse(harness.aggregate.canSettleTerminalDrain())
        XCTAssertFalse(harness.aggregate.settleTerminalDrain())
        XCTAssertEqual(binding.terminalDrainCount, 0)
    }

    func testTerminalDrainRejectsConflictedAggregateWithDrainableSettlement()
        throws {
        let binding = RestoreAggregateBinding(
            throwsDuringStage: true,
            retainsAfterFailedStage: true,
            canDrain: false
        )
        let harness = try makeHarness(binding: binding)

        XCTAssertThrowsError(try harness.aggregate.stage())
        binding.canDrain = true

        XCTAssertFalse(harness.aggregate.canSettleTerminalDrain())
        XCTAssertFalse(harness.aggregate.settleTerminalDrain())
        XCTAssertEqual(binding.terminalDrainCount, 0)
    }

    private func makeHarness(
        binding: RestoreAggregateBinding
    ) throws -> RestoreAggregateHarness {
        let window = BrowserWindowState()
        let tabManager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] }
        )
        window.tabManager = tabManager
        let presentation = try XCTUnwrap(
            WindowSplitPresentationSynchronizer(
                tabManager: { tabManager },
                windows: { [window] },
                selectTabWithoutPersistence: { _, _ in },
                publishPreparedSelectionEffects: { _, _, _, _ in },
                publishWindowChange: { _ in },
                refreshCompositor: { _ in },
                scheduleWindowSession: { _ in },
                persistWindowSession: { _ in }
            ).prepareSettlement(
                previousGroups: [],
                replacementGroups: [],
                affectedGroupIDs: [UUID()],
                terminalParticipants: []
            )
        )
        XCTAssertTrue(presentation.admitAggregateWindowStates([:]))
        let topology = SplitGroupReplacementReceipt(
            store: tabManager.splitGroupStore,
            publisher: tabManager.splitGroupMutations,
            plan: SplitGroupReplacementPlan(
                expected: [], replacement: [], persist: false
            )
        )
        let participants = SplitShortcutMemberRestoreParticipants(
            presentation: presentation,
            retirement: nil,
            topology: topology,
            retirementService: tabManager.shortcutLiveTabRetirement
        )
        return RestoreAggregateHarness(
            aggregate: SplitShortcutMemberRestoreAggregateTransaction(
                binding: binding,
                participants: participants,
                structuralMutations: tabManager
                    .structuralCollectionMutationOwner,
                structuralLookup: tabManager.structuralLookupCoordinator
            ),
            participants: participants
        )
    }
}

@MainActor
private struct RestoreAggregateHarness {
    let aggregate: SplitShortcutMemberRestoreAggregateTransaction
    let participants: SplitShortcutMemberRestoreParticipants
}

@MainActor
private final class RestoreAggregateBinding:
    ShortcutSplitLauncherBindingModelTransaction {
    private enum Failure: Error { case expected }

    private let cancelResult: Bool
    private let rollbackFails: Bool
    private let throwsDuringStage: Bool
    private let retainsAfterFailedStage: Bool
    private var isStaged = false
    private(set) var cancelCount = 0
    private(set) var terminalDrainCount = 0
    var canDrain: Bool

    init(
        cancelResult: Bool = true,
        rollbackFails: Bool = false,
        throwsDuringStage: Bool = false,
        retainsAfterFailedStage: Bool = false,
        canDrain: Bool = true
    ) {
        self.cancelResult = cancelResult
        self.rollbackFails = rollbackFails
        self.throwsDuringStage = throwsDuringStage
        self.retainsAfterFailedStage = retainsAfterFailedStage
        self.canDrain = canDrain
    }

    var exactBindingTabs: [Tab] { [] }
    func validateForStaging() -> Bool { true }
    func stageCatalog() -> Bool { true }
    func prepareStructuralRollbackAfterCatalogStage() -> Bool { true }

    func stageBinding() throws {
        isStaged = true
        if throwsDuringStage { throw Failure.expected }
    }

    func stagedModelIsExact() -> Bool { isStaged }
    func canClaimTerminalModel() -> Bool { isStaged }
    func claimTerminalModel() -> WebViewReplacementTerminalModelClaimOutcome {
        .terminallyDrained
    }
    func claimedModelIsExact() -> Bool { false }
    func publishModelCommit(beforeWindowPublication: () -> Void) {
        beforeWindowPublication()
    }
    func publishTerminalEffects() {}

    func cancelPrepared() -> Bool {
        cancelCount += 1
        return cancelResult
    }

    func rollbackBinding() throws {
        if rollbackFails { throw Failure.expected }
        isStaged = false
    }

    func confirmStructuralRollback() -> Bool { rollbackFails == false }
    func publishRollback() {}
    func retainsModelAfterFailedStage() -> Bool { retainsAfterFailedStage }
    func canSettleTerminalDrain() -> Bool { canDrain }

    func settleTerminalDrain() -> Bool {
        terminalDrainCount += 1
        return canDrain
    }
}
