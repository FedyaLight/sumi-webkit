import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class ShortcutLiveRetirementBatchStateMachineTests: XCTestCase {
    func testResidenceParticipantRecognizesStagedRemovalAndRollback() throws {
        let oracle = try ShortcutLiveRetirementRuntimeOracle.make(hook: .none)
        let plan = try XCTUnwrap(ShortcutLiveTabRetirementPlan(
            pinID: oracle.pin.id,
            windowID: oracle.window.id,
            registry: oracle.tabManager.liveShortcutTabs,
            runtimeConnection: oracle.tabManager.runtimePortConnection
        ))
        let participant = ShortcutLiveResidenceRetirementParticipant(plan: plan)

        XCTAssertTrue(participant.validateForStaging())
        XCTAssertTrue(participant.stage())
        XCTAssertFalse(participant.sourceModelIsExact())
        XCTAssertTrue(participant.stagedModelIsExact())
        XCTAssertTrue(participant.rollback())
        XCTAssertIdentical(
            oracle.tabManager.liveShortcutTabs.tab(
                for: oracle.pin.id,
                in: oracle.window.id
            ),
            oracle.liveTab
        )
    }

    func testBeginAttachmentDriftRejectsWithoutStagingModel() throws {
        let oracle = try ShortcutLiveRetirementRuntimeOracle.make(
            hook: .attachmentABAOnCanRetire(1)
        )

        let result = oracle.tabManager.shortcutLiveTabRetirement.retire(
            pinId: oracle.pin.id,
            in: oracle.window.id
        )

        XCTAssertFalse(result.didRetire)
        assertOriginalModel(oracle)
        XCTAssertEqual(oracle.liveTab.webViewSession.allKnownWebViews.count, 1)
        XCTAssertEqual(oracle.normalDestroyCount, 0)
        XCTAssertEqual(oracle.aggregateDrainDestroyCount, 0)
        XCTAssertTrue(oracle.events.isEmpty)
    }

    func testClaimAttachmentABARollsBackRepositoryAndModel() throws {
        let oracle = try ShortcutLiveRetirementRuntimeOracle.make(
            hook: .attachmentABAOnCanRetire(2)
        )

        let result = oracle.tabManager.shortcutLiveTabRetirement.retire(
            pinId: oracle.pin.id,
            in: oracle.window.id
        )

        XCTAssertFalse(result.didRetire)
        assertOriginalModel(oracle)
        XCTAssertEqual(oracle.canRetireCount, 2)
        XCTAssertEqual(oracle.liveTab.webViewSession.allKnownWebViews.count, 1)
        XCTAssertEqual(oracle.normalDestroyCount, 0)
        XCTAssertEqual(oracle.aggregateDrainDestroyCount, 0)
        XCTAssertTrue(oracle.events.isEmpty)
    }

    func testPostCommitAttachmentABARestoresModelAndCleansOldGenerationOnce()
        throws {
        let oracle = try ShortcutLiveRetirementRuntimeOracle.make(
            hook: .attachmentABAOnCommittedBegin
        )

        let result = oracle.tabManager.shortcutLiveTabRetirement.retire(
            pinId: oracle.pin.id,
            in: oracle.window.id
        )

        XCTAssertFalse(result.didRetire)
        assertOriginalModel(oracle)
        XCTAssertTrue(oracle.liveTab.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertEqual(oracle.normalDestroyCount, 0)
        XCTAssertEqual(oracle.aggregateDrainDestroyCount, 1)
        XCTAssertEqual(
            oracle.events,
            ["committedBegin", "aggregateDrainDestroy"]
        )
    }

    func testClaimTerminalDrainSettlesTerminalModelWithoutDuplicateRuntime()
        throws {
        let oracle = try ShortcutLiveRetirementRuntimeOracle.make(
            hook: .terminalDrainOnCanRetire(2)
        )
        let lifecycle = StateMachineLifecycleOracle()
        let observer = NotificationCenter.default.addObserver(
            forName: .sumiTabLifecycleDidChange,
            object: oracle.liveTab,
            queue: nil
        ) { _ in lifecycle.increment() }

        let result = oracle.tabManager.shortcutLiveTabRetirement.retire(
            pinId: oracle.pin.id,
            in: oracle.window.id
        )

        XCTAssertTrue(result.didRetire)
        XCTAssertNil(oracle.tabManager.liveShortcutTabs.entry(
            tabId: oracle.liveTab.id
        ))
        XCTAssertNil(oracle.tabManager.tabCollectionMembershipOwner.tab(
            for: oracle.liveTab.id
        ))
        XCTAssertEqual(oracle.terminalDrainEntries, 1)
        XCTAssertEqual(oracle.normalDestroyCount, 0)
        XCTAssertEqual(oracle.aggregateDrainDestroyCount, 0)
        XCTAssertEqual(lifecycle.count, 1)
        XCTAssertEqual(oracle.events, ["persist"])
        NotificationCenter.default.removeObserver(observer)
    }

    private func assertOriginalModel(
        _ oracle: ShortcutLiveRetirementRuntimeOracle
    ) {
        XCTAssertIdentical(
            oracle.tabManager.liveShortcutTabs.tab(
                for: oracle.pin.id,
                in: oracle.window.id
            ),
            oracle.liveTab
        )
        XCTAssertIdentical(
            oracle.tabManager.tabCollectionMembershipOwner.tab(
                for: oracle.liveTab.id
            ),
            oracle.liveTab
        )
        XCTAssertEqual(oracle.window.currentTabId, oracle.liveTab.id)
        XCTAssertEqual(oracle.window.currentShortcutPinId, oracle.pin.id)
    }
}

private final class StateMachineLifecycleOracle: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() { lock.withLock { value += 1 } }
    var count: Int { lock.withLock { value } }
}
