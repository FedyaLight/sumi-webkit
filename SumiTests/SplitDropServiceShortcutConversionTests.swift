import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SplitDropServiceShortcutConversionTests: XCTestCase {
    func testEdgeDropCollapsesTwoMemberSourceAndActivatesExactPin() throws {
        let fixture = try makeFixture(sourceMemberCount: 2)
        let target = SplitDropTarget(
            targetMemberID: .shortcutPin(fixture.targetPins[0].id),
            side: .right,
            targetRect: .zero
        )

        XCTAssertTrue(fixture.service.drop(
            fixture.source,
            on: target,
            in: fixture.window
        ))

        let effect = try XCTUnwrap(fixture.probe.effects.first)
        guard case .shortcutPin(let pinID) = effect.preferredActiveMemberID else {
            return XCTFail("Expected the generated shortcut member to activate")
        }
        let committedTarget = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: fixture.targetGroup.id)
        )
        XCTAssertNil(
            fixture.manager.splitGroupStore.group(id: fixture.sourceGroup.id)
        )
        XCTAssertEqual(committedTarget.memberIDs.count, 3)
        XCTAssertTrue(committedTarget.contains(.shortcutPin(pinID)))
        XCTAssertEqual(fixture.window.splitSelection?.groupID, committedTarget.id)
        XCTAssertEqual(fixture.window.currentShortcutPinId, pinID)
        let liveTab = try XCTUnwrap(fixture.manager.liveShortcutTabs.tab(
            for: pinID,
            in: fixture.window.id
        ))
        XCTAssertEqual(
            fixture.window.currentTabId,
            liveTab.id
        )
        XCTAssertEqual(effect.previousGroups, [fixture.sourceGroup, fixture.targetGroup])
        XCTAssertEqual(
            effect.affectedGroupIDs,
            Set([fixture.sourceGroup.id, fixture.targetGroup.id])
        )
        XCTAssertEqual(
            effect.releasedMembers.map(\.memberID),
            [.regularTab(fixture.sourceCompanions[0].id)]
        )
    }

    func testCenterDropKeepsReducedThreeMemberSourceAndReportsReleasedTarget() throws {
        let fixture = try makeFixture(sourceMemberCount: 3)
        let displacedPinID = fixture.targetPins[0].id
        let target = SplitDropTarget(
            targetMemberID: .shortcutPin(displacedPinID),
            side: .center,
            targetRect: .zero,
            previewStyle: .center
        )

        XCTAssertTrue(fixture.service.drop(
            fixture.source,
            on: target,
            in: fixture.window
        ))

        let effect = try XCTUnwrap(fixture.probe.effects.first)
        let reducedSource = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: fixture.sourceGroup.id)
        )
        let committedTarget = try XCTUnwrap(
            fixture.manager.splitGroupStore.group(id: fixture.targetGroup.id)
        )
        XCTAssertEqual(
            Set(reducedSource.memberIDs),
            Set(fixture.sourceCompanions.map { .regularTab($0.id) })
        )
        XCTAssertFalse(committedTarget.contains(.shortcutPin(displacedPinID)))
        XCTAssertTrue(committedTarget.contains(effect.preferredActiveMemberID))
        XCTAssertEqual(
            effect.releasedMembers.map(\.memberID),
            [.shortcutPin(displacedPinID)]
        )
        XCTAssertEqual(
            fixture.window.splitSelection,
            WindowSplitSelection(
                groupID: committedTarget.id,
                activeMemberID: effect.preferredActiveMemberID
            )
        )
        XCTAssertEqual(
            fixture.window.currentShortcutPinId,
            effect.preferredActiveMemberID.shortcutPinID
        )
    }

    func testFullTargetRejectsEdgeDropWithoutConversionMutation() throws {
        let fixture = try makeFixture(
            sourceMemberCount: 2,
            targetMemberCount: SumiDomain.SplitGroup.maximumMembers
        )
        let expectedGroups = fixture.manager.splitGroupStore.groups
        let expectedPins = fixture.manager.shortcutPinCollectionStateOwner
            .spacePinnedPins(for: fixture.space.id).map(\.id)

        XCTAssertFalse(fixture.service.drop(
            fixture.source,
            on: SplitDropTarget(
                targetMemberID: .shortcutPin(fixture.targetPins[0].id),
                side: .right,
                targetRect: .zero
            ),
            in: fixture.window
        ))

        XCTAssertEqual(fixture.manager.splitGroupStore.groups, expectedGroups)
        XCTAssertEqual(
            fixture.manager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: fixture.space.id).map(\.id),
            expectedPins
        )
        XCTAssertTrue(
            fixture.manager.regularTabCollectionOwner.contains(fixture.source)
        )
        XCTAssertTrue(fixture.probe.effects.isEmpty)
        XCTAssertEqual(fixture.probe.limitCount, 1)
    }
}

@MainActor
private extension SplitDropServiceShortcutConversionTests {
    struct Fixture {
        let manager: TabManager
        let window: BrowserWindowState
        let space: Space
        let source: Tab
        let sourceCompanions: [Tab]
        let sourceGroup: SplitGroup
        let targetPins: [ShortcutPin]
        let targetGroup: SplitGroup
        let service: SplitDropService
        let probe: Probe
    }

    final class Probe {
        var effects: [SplitDropCommitEffect] = []
        var limitCount = 0
    }

    func makeFixture(
        sourceMemberCount: Int,
        targetMemberCount: Int = 2
    ) throws -> Fixture {
        let window = BrowserWindowState()
        let manager = try makeInMemoryTabManager(
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            primaryTrackedWindowId: { _ in window.id }
        )
        window.tabManager = manager
        let space = manager.spaceServices.catalog.createSpace(name: "Space")
        let source = manager.regularTabLifecycleOwner.createNewTab(
            url: "https://drop-source.example",
            in: space,
            activate: false
        )
        let companions = (1..<sourceMemberCount).map { index in
            manager.regularTabLifecycleOwner.createNewTab(
                url: "https://drop-companion-\(index).example",
                in: space,
                activate: false
            )
        }
        let sourceGroup = try XCTUnwrap(SplitGroup.make(
            members: [.regularTab(source.id)] + companions.map {
                .regularTab($0.id)
            },
            layoutKind: .vertical,
            container: .regularTabs(spaceId: space.id)
        ))
        let pins = (0..<targetMemberCount).map {
            ShortcutPin(
                id: UUID(),
                role: .spacePinned,
                spaceId: space.id,
                index: $0,
                launchURL: URL(string: "https://drop-pin-\($0).example")!,
                title: "Pin \($0)"
            )
        }
        manager.structuralCollectionMutationOwner.setSpacePinnedShortcuts(
            pins,
            for: space.id
        )
        let targetGroup = try XCTUnwrap(SplitGroup.make(
            members: pins.map {
                .shortcutPin(
                    $0.id,
                    returnPlacement: .spacePinned(
                        spaceId: space.id,
                        folderId: nil,
                        index: $0.index
                    )
                )
            },
            layoutKind: .vertical,
            container: .shortcutSidebar(
                spaceId: space.id,
                profileId: nil,
                folderId: nil,
                index: 0
            )
        ))
        XCTAssertTrue(manager.splitGroupMutations.replaceAll(
            expected: [],
            with: [sourceGroup, targetGroup],
            persist: false
        ))
        window.currentSpaceId = space.id
        window.currentTabId = source.id
        window.splitSelection = WindowSplitSelection(
            groupID: sourceGroup.id,
            activeMemberID: .regularTab(source.id)
        )
        let probe = Probe()
        let launcherPlacement = ShortcutSplitLauncherPlacementService(
            tabManager: { manager }
        )
        let presentations = WindowSplitPresentationSynchronizer(
            tabManager: { manager },
            windows: { [window] },
            selectTabWithoutPersistence: { tab, state in
                _ = WindowTabSelectionStateApplicator.apply(
                    tab,
                    to: state,
                    updateSpaceFromTab: true,
                    rememberSelection: true
                )
            },
            refreshCompositor: { _ in },
            scheduleWindowSession: { _ in },
            persistWindowSession: { _ in }
        )
        let service = SplitDropService(
            tabManager: { manager },
            memberResolver: SplitRuntimeMemberResolver(
                tabManager: { manager }
            ),
            launcherPlacement: launcherPlacement,
            reconcileAfterCommit: { effect in
                probe.effects.append(effect)
                presentations.synchronize(
                    previousGroups: effect.previousGroups,
                    affectedGroupIDs: effect.affectedGroupIDs,
                    preferredSelections: [
                        effect.callerWindowID: WindowSplitSelection(
                            groupID: effect.targetGroupID,
                            activeMemberID: effect.preferredActiveMemberID
                        )
                    ]
                )
            },
            notifyLimit: { _ in probe.limitCount += 1 }
        )
        return Fixture(
            manager: manager,
            window: window,
            space: space,
            source: source,
            sourceCompanions: companions,
            sourceGroup: sourceGroup,
            targetPins: pins,
            targetGroup: targetGroup,
            service: service,
            probe: probe
        )
    }
}

private extension SplitMemberID {
    var shortcutPinID: UUID? {
        guard case .shortcutPin(let pinID) = self else { return nil }
        return pinID
    }
}
