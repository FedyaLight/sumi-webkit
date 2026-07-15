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

    func testClaimTopologyDriftPreservesForeignTopologyAndRestoresSource()
        throws {
        var oracle: ShortcutLiveRetirementRuntimeOracle!
        var foreignGroup: SplitGroup?
        oracle = try ShortcutLiveRetirementRuntimeOracle.make(
            hook: .actionOnCanRetire(2) {
                guard let current = oracle.tabManager.splitGroupStore.groups
                    .first,
                      let changed = current.changingLayout(to: .horizontal)
                else { return }
                XCTAssertTrue(oracle.tabManager.splitGroupMutations.replace(
                    current, with: changed, persist: false
                ))
                foreignGroup = changed
            }
        )
        let spaceID = try XCTUnwrap(oracle.pin.spaceId)
        let companions = try (1...2).map { index in
            try XCTUnwrap(oracle.tabManager.shortcutPinStoreOwner.insert(
                PublicationFixture.makePin(index: index, spaceID: spaceID),
                at: index
            ))
        }
        let group = try XCTUnwrap(SplitGroup.make(
            members: ([oracle.pin] + companions).enumerated().map { index, pin in
                .shortcutPin(
                    pin.id,
                    returnPlacement: .spacePinned(
                        spaceId: spaceID,
                        folderId: nil,
                        index: index
                    )
                )
            },
            layoutKind: .vertical,
            container: .regularTabs(spaceId: spaceID)
        ))
        XCTAssertTrue(oracle.tabManager.splitGroupMutations.insert(
            group, persist: false
        ))
        oracle.window.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .shortcutPin(oracle.pin.id)
        )

        oracle.tabManager.shortcutPinCommandOwner.removeShortcutPin(oracle.pin)

        XCTAssertIdentical(
            oracle.tabManager.liveShortcutTabs.tab(
                for: oracle.pin.id, in: oracle.window.id
            ),
            oracle.liveTab
        )
        XCTAssertIdentical(
            oracle.tabManager.tabCollectionMembershipOwner.tab(
                for: oracle.liveTab.id
            ),
            oracle.liveTab
        )
        XCTAssertNotNil(oracle.tabManager.shortcutPinCollectionStateOwner
            .shortcutPin(by: oracle.pin.id))
        let terminalGroup = try XCTUnwrap(foreignGroup)
        XCTAssertEqual(
            oracle.tabManager.splitGroupStore.group(id: group.id),
            terminalGroup
        )
        XCTAssertEqual(oracle.window.splitSelection?.groupID, terminalGroup.id)
        XCTAssertTrue(terminalGroup.contains(
            try XCTUnwrap(oracle.window.splitSelection?.activeMemberID)
        ))
        XCTAssertNotEqual(oracle.window.currentShortcutPinId, oracle.pin.id)
        XCTAssertEqual(oracle.normalDestroyCount, 0)
        XCTAssertEqual(oracle.aggregateDrainDestroyCount, 0)
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
