import Combine
import Observation
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

    func testDisplayedCenterDropPublishesTerminalReleasedLauncherAggregateAndPreservesReentrantLayout() throws {
        let fixture = try makeFixture(sourceMemberCount: 3)
        let restorationSpace = fixture.manager.spaceServices.catalog.createSpace(
            name: "Restoration",
            profileId: fixture.restorationProfile.id
        )
        let displacedPin = fixture.targetPins[0]
        let retainedPin = fixture.targetPins[1]
        let targetGroup = try XCTUnwrap(SplitGroup.make(
            members: [
                .shortcutPin(
                    displacedPin.id,
                    returnPlacement: .spacePinned(
                        spaceId: restorationSpace.id,
                        folderId: nil,
                        index: 0
                    )
                ),
                try XCTUnwrap(
                    fixture.targetGroup.member(
                        for: .shortcutPin(retainedPin.id)
                    )
                ),
            ],
            layoutKind: fixture.targetGroup.layoutKind,
            container: fixture.targetGroup.container
        ))
        XCTAssertTrue(fixture.manager.splitGroupMutations.replace(
            fixture.targetGroup,
            with: targetGroup,
            persist: false
        ))
        let displacedTab = try XCTUnwrap(
            fixture.manager.shortcutTabMaterializer.materialize(
                displacedPin,
                in: fixture.window.id,
                currentSpaceId: fixture.space.id
            )
        )
        fixture.window.selectedShortcutPinForSpace[fixture.space.id] =
            displacedPin.id
        fixture.window.selectionHistory.recordSelection(
            .shortcutPin(displacedPin.id),
            in: fixture.space.id
        )

        let observation = DisplayedCenterDropWindowObservationOracle()
        var structuralEvents = 0
        let structureCancellable = fixture.manager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        withObservationTracking {
            _ = fixture.window.currentTabId
            _ = fixture.window.currentShortcutPinId
            _ = fixture.window.splitSelection
            _ = fixture.window.selectedShortcutPinForSpace
            _ = fixture.window.selectionHistory
        } onChange: {
            MainActor.assumeIsolated {
                guard observation.didInspectFirstPublication == false else {
                    return
                }
                observation.didInspectFirstPublication = true
                guard let terminalTarget = fixture.manager.splitGroupStore.group(
                    id: targetGroup.id
                ), let terminalSource = fixture.manager.splitGroupStore.group(
                    id: fixture.sourceGroup.id
                ), let generatedPinID = terminalTarget.memberIDs.compactMap({ memberID in
                    guard case .shortcutPin(let pinID) = memberID,
                          pinID != retainedPin.id else { return nil }
                    return pinID
                }).first(where: { $0 != displacedPin.id }),
                    let generatedPin = fixture.manager
                    .shortcutPinCollectionStateOwner.shortcutPin(
                        by: generatedPinID
                    ) else {
                    return XCTFail(
                        "First window publication must expose the terminal launcher aggregate"
                    )
                }
                XCTAssertFalse(
                    terminalTarget.contains(.regularTab(fixture.source.id))
                )
                XCTAssertFalse(
                    terminalSource.contains(.regularTab(fixture.source.id))
                )
                XCTAssertEqual(
                    Set(terminalSource.memberIDs),
                    Set(fixture.sourceCompanions.map { .regularTab($0.id) })
                )
                XCTAssertFalse(
                    terminalTarget.contains(.shortcutPin(displacedPin.id))
                )
                XCTAssertTrue(
                    terminalTarget.contains(.shortcutPin(generatedPin.id))
                )
                XCTAssertFalse(
                    fixture.manager.regularTabCollectionOwner.contains(
                        fixture.source
                    )
                )
                XCTAssertIdentical(
                    fixture.manager.liveShortcutTabs.tab(
                        for: generatedPin.id,
                        in: fixture.window.id
                    ),
                    fixture.source
                )
                let displacedResidence = fixture.manager.liveShortcutTabs
                    .entry(containing: displacedTab)
                XCTAssertEqual(
                    displacedResidence?.presentationPage.page.spaceID,
                    restorationSpace.id
                )
                XCTAssertEqual(displacedTab.spaceId, restorationSpace.id)
                XCTAssertEqual(
                    displacedTab.profileId,
                    fixture.restorationProfile.id
                )
                XCTAssertEqual(
                    fixture.manager.shortcutPinCollectionStateOwner
                        .shortcutPin(by: displacedPin.id)?.spaceId,
                    restorationSpace.id
                )
                XCTAssertEqual(
                    fixture.window.splitSelection,
                    WindowSplitSelection(
                        groupID: targetGroup.id,
                        activeMemberID: .shortcutPin(generatedPin.id)
                    )
                )
                XCTAssertEqual(
                    fixture.window.currentShortcutPinId,
                    generatedPin.id
                )
                XCTAssertEqual(
                    fixture.probe.profileAssignmentTabIDs.filter {
                        $0 == displacedTab.id
                    }.count,
                    0
                )
                XCTAssertEqual(fixture.probe.sessionWriteCount, 0)

                guard let horizontal = terminalTarget.changingLayout(
                    to: .horizontal
                ) else {
                    return XCTFail(
                        "Expected a valid reentrant target layout"
                    )
                }
                let expected = fixture.manager.splitGroupStore.groups
                observation.didCommitReentrantMutation = fixture.manager
                    .splitGroupMutations.replaceAll(
                        expected: expected,
                        with: expected.map {
                            $0.id == horizontal.id ? horizontal : $0
                        },
                        persist: false
                    )
                observation.reentrantTarget = horizontal
            }
        }
        structuralEvents = 0

        XCTAssertTrue(fixture.service.drop(
            fixture.source,
            on: SplitDropTarget(
                targetMemberID: .shortcutPin(displacedPin.id),
                side: .center,
                targetRect: .zero,
                previewStyle: .center
            ),
            in: fixture.window
        ))

        XCTAssertTrue(observation.didInspectFirstPublication)
        XCTAssertTrue(observation.didCommitReentrantMutation)
        XCTAssertEqual(
            fixture.manager.splitGroupStore.group(id: targetGroup.id),
            observation.reentrantTarget
        )
        XCTAssertEqual(
            fixture.probe.effects.first?.releasedMembers.map(\.memberID),
            [.shortcutPin(displacedPin.id)]
        )
        XCTAssertEqual(
            fixture.probe.profileAssignmentTabIDs.filter {
                $0 == displacedTab.id
            }.count,
            1
        )
        XCTAssertGreaterThan(fixture.probe.sessionWriteCount, 0)
        XCTAssertEqual(structuralEvents, 1)
        _ = structureCancellable
    }
}

@MainActor
private extension SplitDropServiceShortcutConversionTests {
    @MainActor
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
        let restorationProfile: Profile
    }

    final class Probe {
        var effects: [SplitDropCommitEffect] = []
        var limitCount = 0
        var profileAssignmentTabIDs: [UUID] = []
        var sessionWriteCount = 0
    }

    final class RecordingSplitDropPresentations:
        SplitDropPresentationReconciling {
        private let presentations: WindowSplitPresentationSynchronizer
        private let probe: Probe

        init(
            presentations: WindowSplitPresentationSynchronizer,
            probe: Probe
        ) {
            self.presentations = presentations
            self.probe = probe
        }

        func reconcile(_ effect: SplitDropCommitEffect) {
            probe.effects.append(effect)
            presentations.reconcile(effect)
        }
    }

    func makeFixture(
        sourceMemberCount: Int,
        targetMemberCount: Int = 2
    ) throws -> Fixture {
        let window = BrowserWindowState()
        let sourceProfile = Profile(name: "Source")
        let restorationProfile = Profile(name: "Restoration")
        let profiles = [
            sourceProfile.id: sourceProfile,
            restorationProfile.id: restorationProfile,
        ]
        let probe = Probe()
        let manager = try makeInMemoryTabManager(
            currentProfileId: { sourceProfile.id },
            defaultProfileId: { sourceProfile.id },
            profile: { profiles[$0] },
            windowState: { $0 == window.id ? window : nil },
            windows: { [(window.id, window)] },
            primaryTrackedWindowId: { _ in window.id },
            persistWindowSession: { _ in
                probe.sessionWriteCount += 1
            },
            executeProfileAssignment: { tab, _, intent in
                probe.profileAssignmentTabIDs.append(tab.id)
                return tab.profileAssignment.commit(intent)
                    ? .committed
                    : .stale
            }
        )
        window.tabManager = manager
        let space = manager.spaceServices.catalog.createSpace(
            name: "Space",
            profileId: sourceProfile.id
        )
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
        let launcherPlacement = ShortcutSplitLauncherPlacementService(
            tabManager: manager
        )
        let members = SplitRuntimeMemberResolver(tabManager: { manager })
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
            publishPreparedSelectionEffects: { _, _, _, _ in
                /* The drop fixture records selection through its model probe. */
            },
            publishWindowChange: { _ in
                /* No window-update subscriber is installed by this fixture. */
            },
            refreshCompositor: { _ in },
            scheduleWindowSession: { _ in },
            persistWindowSession: { _ in }
        )
        let placeholderReplacements = SplitPlaceholderReplacementPlanner(
            query: SplitPlaceholderReplacementQuery(
                regularTabs: manager.regularTabCollectionOwner,
                splitGroups: manager.splitGroupStore,
                membership: manager.splitGroupMembership,
                liveShortcuts: manager.liveShortcutTabs,
                members: members
            ),
            launcher: launcherPlacement,
            splitMutations: manager.splitGroupMutations,
            retirement: EmptySplitPlaceholderRetirementService(
                regularTabs: manager.regularTabCollectionOwner,
                selection: manager.selectionStateOwner,
                structuralLookup: manager.structuralLookupCoordinator,
                persistence: manager.structuralPersistence,
                runtimeConnection: manager.runtimePortConnection,
                runtimeCleanup: RegularTabClosureRuntimeCleanup(
                    membership: manager.tabCollectionMembershipOwner
                )
            ),
            presentations: RecordingSplitDropPresentations(
                presentations: presentations,
                probe: probe
            )
        )
        let recordingPresentations = RecordingSplitDropPresentations(
            presentations: presentations,
            probe: probe
        )
        let service = SplitDropService(
            tabManager: { manager },
            memberResolver: members,
            launcherPlacement: launcherPlacement,
            placeholderReplacements: placeholderReplacements,
            presentations: recordingPresentations,
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
            probe: probe,
            restorationProfile: restorationProfile
        )
    }
}

@MainActor
private final class DisplayedCenterDropWindowObservationOracle {
    var didInspectFirstPublication = false
    var didCommitReentrantMutation = false
    var reentrantTarget: SplitGroup?
}

private extension SplitMemberID {
    var shortcutPinID: UUID? {
        guard case .shortcutPin(let pinID) = self else { return nil }
        return pinID
    }
}
