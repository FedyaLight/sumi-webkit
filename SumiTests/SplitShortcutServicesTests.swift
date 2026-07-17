import AppKit
import Combine
import Observation
import SumiDomain
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SplitShortcutServicesTests: XCTestCase {
    func testLiveTabCloseRoutesHostedSplitThroughAtomicUnload() throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            retirement: .accepting
        )
        let liveTab = try XCTUnwrap(
            fixture.tabManager.liveShortcutTabs.tab(
                for: fixture.firstPin.id,
                in: fixture.windowState.id
            )
        )

        XCTAssertTrue(
            fixture.browserManager.shortcutLiveTabClose.close(
                liveTab,
                in: fixture.windowState,
                presentNotification: false
            )
        )
        XCTAssertEqual(
            fixture.tabManager.splitGroupStore.group(id: fixture.group.id),
            fixture.group
        )
        XCTAssertNil(fixture.windowState.splitSelection)
        XCTAssertEqual(
            fixture.windowState.currentTabId,
            fixture.fallback?.id
        )
        XCTAssertTrue(fixture.pins.allSatisfy {
            fixture.tabManager.liveShortcutTabs.tab(
                for: $0.id,
                in: fixture.windowState.id
            ) == nil
        })
    }

    func testInsertionPreviewRejectsStaleSameIDCanonicalFallback() throws {
        let fixture = try makeFixture()
        let candidate = try makePin(
            url: "https://insertion-preview.example",
            spaceId: fixture.space.id,
            index: fixture.pins.count
        )
        let catalog = ShortcutSplitLauncherCatalogTransaction(
            pinStore: fixture.tabManager.shortcutPinStoreOwner,
            pins: fixture.tabManager.shortcutPinCollectionStateOwner
        )
        let insertion = try XCTUnwrap(
            catalog.prepareInsertion(candidate, at: fixture.pins.count)
        )
        fixture.tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts(
                fixture.pins + [candidate.refreshed()],
                for: fixture.space.id
            )

        XCTAssertNil(
            insertion.presentationPreview.resolvePin(
                withID: candidate.id,
                canonical: {
                    fixture.tabManager.shortcutPinCollectionStateOwner
                        .shortcutPin(by: candidate.id)
                }
            )
        )
    }

    func testCanonicalActivationRejectsEquivalentSameIDPinReplacement() throws {
        let fixture = try makeFixture()
        let pin = fixture.firstPin
        let receipt = try XCTUnwrap(
            fixture.tabManager.shortcutPresentationActivation.prepareActivation([
                .init(
                    pinID: pin.id,
                    windowID: fixture.windowState.id,
                    presentationSpaceID: fixture.space.id
                ),
            ])
        )
        var pins = try XCTUnwrap(
            fixture.tabManager.shortcutPinCollectionStateOwner
                .spacePinnedShortcutsSnapshot()[fixture.space.id]
        )
        let index = try XCTUnwrap(pins.firstIndex { $0.id == pin.id })
        pins[index] = pin.refreshed()
        fixture.tabManager.shortcutPinCollectionStateOwner
            .replaceSpacePinnedShortcuts([fixture.space.id: pins])

        XCTAssertFalse(receipt.stage())
    }

    func testRestoreDrainsCommittedRuntimeOnceWithoutOverwritingTopologyDrift()
        throws {
        var fixture: SplitServiceFixture!
        var service: SplitShortcutMemberRestoreService!
        var normalDestroyCount = 0
        var drainDestroyCount = 0
        var reentrantResults: [Bool] = []
        var foreignGroup: SplitGroup!
        let retirement = TestRuntimePorts.RetirementCapabilities(
            canRetire: { _ in true },
            beginCommitted: { _ in
                guard let changed = fixture.group.changingLayout(
                    to: .horizontal
                ) else { return false }
                foreignGroup = changed
                fixture.tabManager.splitGroupStore.replaceAll(
                    with: [changed]
                )
                return true
            },
            committedRetirementIsExact: { _ in true },
            destroy: { _ in normalDestroyCount += 1 },
            destroyAfterTerminalDrain: { _ in
                drainDestroyCount += 1
                reentrantResults.append(service.restoreShortcutSplitMember(
                    .shortcutPin(fixture.firstPin.id),
                    from: fixture.group,
                    in: fixture.windowState,
                    preserveLiveInstance: false
                ))
            }
        )
        fixture = try makeFixture(
            materializeMembers: true,
            memberCount: 3,
            retirement: retirement
        )
        let retired = try XCTUnwrap(
            fixture.tabManager.liveShortcutTabs.tab(
                for: fixture.firstPin.id,
                in: fixture.windowState.id
            )
        )
        retired.replaceUntrackedWebView(WKWebView())
        service = makeMemberRestoreService(fixture)

        XCTAssertFalse(service.restoreShortcutSplitMember(
            .shortcutPin(fixture.firstPin.id),
            from: fixture.group,
            in: fixture.windowState,
            preserveLiveInstance: false
        ))

        XCTAssertEqual(
            fixture.tabManager.splitGroupStore.groups,
            [foreignGroup]
        )
        XCTAssertTrue(retired.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertEqual(normalDestroyCount, 0)
        XCTAssertEqual(drainDestroyCount, 1)
        XCTAssertEqual(reentrantResults, [false])
        XCTAssertEqual(fixture.probe.sessionWrites, 0)
    }

    func testRestoreAttachmentABADrainsCommittedRuntimeWithoutScopedEffects()
        throws {
        var fixture: SplitServiceFixture!
        var runtime: RuntimePortRegistry!
        var normalDestroyCount = 0
        var drainDestroyCount = 0
        let retirement = TestRuntimePorts.RetirementCapabilities(
            canRetire: { _ in true },
            beginCommitted: { _ in
                fixture.runtimeAttachment.detach()
                fixture.runtimeAttachment.attach(runtime)
                return true
            },
            committedRetirementIsExact: { _ in true },
            destroy: { _ in normalDestroyCount += 1 },
            destroyAfterTerminalDrain: { _ in drainDestroyCount += 1 }
        )
        fixture = try makeFixture(
            materializeMembers: true,
            memberCount: 3,
            retirement: retirement
        )
        runtime = fixture.tabManager.runtimePortConnection.requireLease()
        let retired = try XCTUnwrap(
            fixture.tabManager.liveShortcutTabs.tab(
                for: fixture.firstPin.id,
                in: fixture.windowState.id
            )
        )
        retired.replaceUntrackedWebView(WKWebView())

        XCTAssertFalse(makeMemberRestoreService(fixture)
            .restoreShortcutSplitMember(
                .shortcutPin(fixture.firstPin.id),
                from: fixture.group,
                in: fixture.windowState,
                preserveLiveInstance: false
            ))

        XCTAssertTrue(retired.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertEqual(normalDestroyCount, 0)
        XCTAssertEqual(drainDestroyCount, 1)
        XCTAssertEqual(fixture.probe.sessionWrites, 0)
    }

    func testStaleWindowSpaceDoesNotSelectGlobalFirstTab() throws {
        let fixture = try makeFixture()
        let unrelatedSpace = try XCTUnwrap(
            fixture.tabManager.sidebarSpaceLifecycle.createSpace(
                name: "Unrelated",
                icon: SumiPersistentGlyph.spaceDefaultIconValue,
                profileID: nil
            )
        )
        let unrelated = fixture.tabManager.regularTabLifecycleOwner
            .createNewTab(
                url: "https://unrelated.example",
                in: unrelatedSpace,
                activate: false
            )
        fixture.windowState.currentSpaceId = UUID()
        fixture.windowState.currentTabId = fixture.firstPin.id
        fixture.windowState.currentShortcutPinId = fixture.firstPin.id

        makeHostedUnloadService(fixture).unloadShortcutHostedSplitGroup(
            fixture.group,
            in: fixture.windowState
        )

        XCTAssertNotEqual(fixture.windowState.currentTabId, unrelated.id)
        XCTAssertNil(fixture.windowState.currentTabId)
        XCTAssertNil(fixture.windowState.currentShortcutPinId)
        XCTAssertTrue(fixture.windowState.isShowingEmptyState)
        XCTAssertEqual(fixture.probe.sessionWrites, 1)
    }

    func testHostedUnloadLeavesDurableGroupUntouchedDuringRuntimeTeardown() throws {
        let fixture = try makeFixture(materializeMembers: true)
        let cancellable = observeStructure(in: fixture)

        makeHostedUnloadService(fixture).unloadShortcutHostedSplitGroup(
            fixture.group,
            in: fixture.windowState
        )

        XCTAssertEqual(fixture.probe.structuralEvents, 1)
        XCTAssertEqual(fixture.probe.eventsSeenAtUnload, [1, 1])
        XCTAssertEqual(
            fixture.windowState.currentTabId,
            try XCTUnwrap(fixture.fallback).id
        )
        XCTAssertTrue(
            fixture.tabManager.liveShortcutTabs
                .entries(for: fixture.firstPin.id).isEmpty
        )
        XCTAssertTrue(
            fixture.tabManager.liveShortcutTabs
                .entries(for: fixture.secondPin.id).isEmpty
        )
        XCTAssertEqual(
            fixture.tabManager.splitGroupStore.group(id: fixture.group.id),
            fixture.group
        )
        XCTAssertNil(fixture.windowState.splitSelection)
        XCTAssertEqual(fixture.probe.sessionWrites, 1)
        _ = cancellable
    }

    func testRestoreClosingMemberPublishesBeforeTeardown() throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            windowCount: 2,
            retirement: .accepting
        )
        let secondWindow = fixture.windowStates[1]
        secondWindow.splitSelection = WindowSplitSelection(
            groupID: fixture.group.id,
            activeMemberID: .shortcutPin(fixture.secondPin.id)
        )
        let service = makeMemberRestoreService(fixture)
        var terminalSnapshots: [Bool] = []
        var reentrantResults: [Bool] = []
        let cancellable = fixture.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink {
                fixture.probe.structuralEvents += 1
                terminalSnapshots.append(
                    fixture.tabManager.splitGroupStore.group(
                        id: fixture.group.id
                    ) == nil
                        && fixture.tabManager.liveShortcutTabs.entries(
                            for: fixture.firstPin.id
                        ).isEmpty
                        && fixture.tabManager.liveShortcutTabs.entries(
                            for: fixture.secondPin.id
                        ).count == 2
                        && fixture.windowStates.allSatisfy {
                            $0.splitSelection == nil
                        }
                )
                reentrantResults.append(service.restoreShortcutSplitMember(
                    .shortcutPin(fixture.firstPin.id),
                    from: fixture.group,
                    in: fixture.windowState,
                    preserveLiveInstance: false
                ))
            }
        fixture.probe.structuralEvents = 0

        XCTAssertTrue(service.restoreShortcutSplitMember(
            .shortcutPin(fixture.firstPin.id),
            from: fixture.group,
            in: fixture.windowState,
            preserveLiveInstance: false
        ))

        XCTAssertEqual(fixture.probe.structuralEvents, 1)
        XCTAssertEqual(terminalSnapshots, [true])
        XCTAssertEqual(reentrantResults, [false])
        XCTAssertEqual(fixture.probe.eventsSeenAtUnload, [1])
        XCTAssertEqual(
            fixture.windowState.currentTabId,
            fixture.tabManager.liveShortcutTabs.tab(
                for: fixture.secondPin.id,
                in: fixture.windowState.id
            )?.id
        )
        XCTAssertEqual(
            secondWindow.currentTabId,
            fixture.tabManager.liveShortcutTabs.tab(
                for: fixture.secondPin.id,
                in: secondWindow.id
            )?.id
        )
        XCTAssertTrue(
            fixture.tabManager.liveShortcutTabs
                .entries(for: fixture.firstPin.id).isEmpty
        )
        XCTAssertEqual(
            fixture.tabManager.liveShortcutTabs
                .entries(for: fixture.secondPin.id).count,
            2
        )
        XCTAssertNil(
            fixture.tabManager.splitGroupStore.group(id: fixture.group.id)
        )
        XCTAssertNil(fixture.windowState.splitSelection)
        XCTAssertNil(secondWindow.splitSelection)
        XCTAssertNotNil(fixture.windowSessionSnapshotStore.loadSnapshot())
        XCTAssertEqual(
            fixture.tabManager.windowSessionPersistenceCoordinator.flush(),
            0
        )
        _ = cancellable
    }

    func testRestoreProjectsRemainingGroupIntoEveryPresentingWindow() throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            memberCount: 3,
            windowCount: 2,
            retirement: .accepting
        )
        let secondWindow = fixture.windowStates[1]
        secondWindow.splitSelection = WindowSplitSelection(
            groupID: fixture.group.id,
            activeMemberID: .shortcutPin(fixture.firstPin.id)
        )
        let removedMemberID = SplitMemberID.shortcutPin(fixture.firstPin.id)
        let expectedGroup = try XCTUnwrap(
            fixture.group.removingMember(removedMemberID)
        )

        XCTAssertTrue(makeMemberRestoreService(fixture).restoreShortcutSplitMember(
            removedMemberID,
            from: fixture.group,
            in: fixture.windowState,
            preserveLiveInstance: false
        ))

        XCTAssertEqual(
            fixture.tabManager.splitGroupStore.group(id: fixture.group.id),
            expectedGroup
        )
        for windowState in fixture.windowStates {
            XCTAssertEqual(
                windowState.splitSelection,
                WindowSplitSelection(
                    groupID: expectedGroup.id,
                    activeMemberID: .shortcutPin(fixture.secondPin.id)
                )
            )
            XCTAssertEqual(
                windowState.currentTabId,
                fixture.tabManager.liveShortcutTabs.tab(
                    for: fixture.secondPin.id,
                    in: windowState.id
                )?.id
            )
        }
        XCTAssertEqual(
            fixture.tabManager.liveShortcutTabs
                .entries(for: fixture.secondPin.id).count,
            2
        )
        XCTAssertNotNil(fixture.windowSessionSnapshotStore.loadSnapshot())
        XCTAssertEqual(
            fixture.tabManager.windowSessionPersistenceCoordinator.flush(),
            0
        )
    }

    func testRestoreProxyMemberWithoutLiveInstanceCommitsWithoutRetirement()
        throws {
        let fixture = try makeFixture(
            materializeMembers: false,
            retirement: .rejecting
        )
        let cancellable = observeStructure(in: fixture)

        XCTAssertTrue(makeMemberRestoreService(fixture)
            .restoreShortcutSplitMember(
                .shortcutPin(fixture.firstPin.id),
                from: fixture.group,
                in: fixture.windowState,
                preserveLiveInstance: false
            ))

        XCTAssertNil(
            fixture.tabManager.splitGroupStore.group(id: fixture.group.id)
        )
        XCTAssertTrue(
            fixture.tabManager.liveShortcutTabs
                .entries(for: fixture.firstPin.id).isEmpty
        )
        XCTAssertEqual(fixture.probe.structuralEvents, 1)
        XCTAssertTrue(fixture.probe.eventsSeenAtUnload.isEmpty)
        _ = cancellable
    }

    func testRestoreFirstWindowCallbackSeesTerminalAggregateAndPreservesReentry()
        throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            memberCount: 3,
            retirement: .accepting
        )
        let removedMemberID = SplitMemberID.shortcutPin(fixture.firstPin.id)
        let remaining = try XCTUnwrap(
            fixture.group.removingMember(removedMemberID)
        )
        let observation = SplitTerminalObservationOracle()

        withObservationTracking {
            _ = fixture.windowState.currentTabId
            _ = fixture.windowState.splitSelection
        } onChange: {
            MainActor.assumeIsolated {
                guard observation.reentrantGroup == nil else { return }
                let current = fixture.tabManager.splitGroupStore.group(
                    id: fixture.group.id
                )
                observation.sawTerminalState = current == remaining
                    && fixture.windowState.splitSelection
                    == WindowSplitSelection(
                        groupID: remaining.id,
                        activeMemberID: .shortcutPin(fixture.secondPin.id)
                    )
                    && fixture.tabManager.liveShortcutTabs
                    .entries(for: fixture.firstPin.id).isEmpty
                guard let current,
                      let changed = current.changingLayout(to: .horizontal),
                      fixture.tabManager.splitGroupMutations.replace(
                          current,
                          with: changed,
                          persist: false
                      ) else { return }
                observation.reentrantGroup = changed
            }
        }

        XCTAssertTrue(makeMemberRestoreService(fixture)
            .restoreShortcutSplitMember(
                removedMemberID,
                from: fixture.group,
                in: fixture.windowState,
                preserveLiveInstance: false
            ))

        XCTAssertTrue(observation.sawTerminalState)
        XCTAssertEqual(
            fixture.tabManager.splitGroupStore.group(id: fixture.group.id),
            try XCTUnwrap(observation.reentrantGroup)
        )
    }

    func testFolderOpenCallbackSeesTerminalSplitAndResidenceAggregate()
        throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            memberCount: 3,
            retirement: .accepting
        )
        let folder = try XCTUnwrap(
            fixture.tabManager.sidebarFolderCommands.createFolder(
                in: fixture.space.id,
                name: "Restored"
            )
        )
        let memberID = SplitMemberID.shortcutPin(fixture.firstPin.id)
        let folderMember = SplitMember.shortcutPin(
            fixture.firstPin.id,
            returnPlacement: .spacePinned(
                spaceId: fixture.space.id,
                folderId: folder.id,
                index: 0
            )
        )
        let folderGroup = try XCTUnwrap(
            fixture.group.replacingMember(memberID, with: folderMember)
        )
        XCTAssertTrue(fixture.tabManager.splitGroupMutations.replace(
            fixture.group,
            with: folderGroup,
            persist: false
        ))
        let remaining = try XCTUnwrap(folderGroup.removingMember(memberID))
        let observation = SplitTerminalObservationOracle()

        withObservationTracking {
            _ = folder.isOpen
        } onChange: {
            MainActor.assumeIsolated {
                observation.sawTerminalState = fixture.tabManager
                    .splitGroupStore.group(id: folderGroup.id) == remaining
                    && fixture.windowState.splitSelection
                    == WindowSplitSelection(
                        groupID: remaining.id,
                        activeMemberID: .shortcutPin(fixture.secondPin.id)
                    )
                    && fixture.windowState.currentTabId == fixture.tabManager
                    .liveShortcutTabs.tab(
                        for: fixture.secondPin.id,
                        in: fixture.windowState.id
                    )?.id
                    && fixture.tabManager.liveShortcutTabs
                    .entries(for: fixture.firstPin.id).isEmpty
            }
        }

        XCTAssertTrue(makeMemberRestoreService(fixture)
            .restoreShortcutSplitMember(
                memberID,
                from: folderGroup,
                in: fixture.windowState,
                preserveLiveInstance: false
            ))

        XCTAssertTrue(folder.isOpen)
        XCTAssertTrue(observation.sawTerminalState)
    }

    func testPreparedSettlementRejectsSameIDWindowReplacement() throws {
        let fixture = try makeFixture(materializeMembers: true)
        let originalLiveTab = try XCTUnwrap(
            fixture.tabManager.liveShortcutTabs.tab(
                for: fixture.firstPin.id,
                in: fixture.windowState.id
            )
        )
        var currentWindows = fixture.windowStates
        let presentations = makeTestWindowSplitPresentationSynchronizer(
            browser: fixture.tabManager,
            windows: { currentWindows }
        )
        let prepared = try XCTUnwrap(presentations.prepareSettlement(
            previousGroups: [fixture.group],
            replacementGroups: fixture.tabManager.splitGroupStore.groups,
            affectedGroupIDs: [fixture.group.id],
            terminalParticipants: []
        ))
        currentWindows = [BrowserWindowState(id: fixture.windowState.id)]

        XCTAssertFalse(prepared.stage())
        XCTAssertIdentical(
            fixture.tabManager.liveShortcutTabs.tab(
                for: fixture.firstPin.id,
                in: fixture.windowState.id
            ),
            originalLiveTab
        )
    }

    func testPreparedSettlementRejectsAlreadyReplacedRequiredWindow() throws {
        let fixture = try makeFixture(materializeMembers: true)
        let replacement = BrowserWindowState(id: fixture.windowState.id)
        let presentations = makeTestWindowSplitPresentationSynchronizer(
            browser: fixture.tabManager,
            windows: { [replacement] }
        )

        XCTAssertNil(presentations.prepareSettlement(
            previousGroups: [fixture.group],
            replacementGroups: fixture.tabManager.splitGroupStore.groups,
            affectedGroupIDs: [fixture.group.id],
            standaloneMembers: [
                fixture.windowState.id: .shortcutPin(fixture.firstPin.id),
            ],
            requiredWindows: [fixture.windowState.id: fixture.windowState],
            terminalParticipants: []
        ))
    }

    func testTerminalWindowABAFromUpdateSkipsStaleCompositorSessionAndHandoff()
        throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            memberCount: 3
        )
        var currentWindows = fixture.windowStates
        let replacement = BrowserWindowState(id: fixture.windowState.id)
        var windowChangeCount = 0
        var handoffCount = 0
        let compositorVersion = fixture.windowState.compositorInvalidation
            .compositorVersion
        let update = fixture.tabManager.splitUpdateChannel.stream
            .updates(for: fixture.windowState.id).sink {
                windowChangeCount += 1
                currentWindows = [replacement]
            }
        let presentations = makeTestWindowSplitPresentationSynchronizer(
            browser: fixture.tabManager,
            windows: { currentWindows }
        )
        let service = SplitShortcutMemberRestoreService(
            preparation: SplitShortcutMemberRestorePreparationService(
                splitGroups: fixture.tabManager.splitGroupStore,
                pins: fixture.tabManager.shortcutPinCollectionStateOwner,
                liveShortcuts: fixture.tabManager.liveShortcutTabs,
                runtimeConnection: fixture.tabManager.runtimePortConnection,
                launcherPlacement: makeLauncherPlacementService(fixture)
            ),
            splitMutations: fixture.tabManager.splitGroupMutations,
            shortcutRetirement: fixture.tabManager.shortcutLiveTabRetirement,
            publication: SplitShortcutMemberRestorePublication(
                presentations: presentations,
                folderOpenState: fixture.tabManager.folderOpenState,
                visuals: makeVisuals(fixture) { _ in handoffCount += 1 }
            )
        )

        XCTAssertTrue(service.restoreShortcutSplitMember(
            .shortcutPin(fixture.firstPin.id),
            from: fixture.group,
            in: fixture.windowState
        ))

        XCTAssertEqual(windowChangeCount, 1)
        XCTAssertEqual(
            fixture.windowState.compositorInvalidation.compositorVersion,
            compositorVersion
        )
        XCTAssertEqual(
            fixture.tabManager.windowSessionPersistenceCoordinator.flush(),
            0
        )
        XCTAssertEqual(handoffCount, 0)
        XCTAssertNil(replacement.currentTabId)
        XCTAssertNil(replacement.splitSelection)
        _ = update
    }

    func testPreparedSettlementRejectsSameIDRegularMemberReplacement() throws {
        let fixture = try makeFixture()
        let original = try XCTUnwrap(fixture.fallback)
        let companion = fixture.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://companion.example",
            in: fixture.space,
            activate: false
        )
        let group = try XCTUnwrap(SplitGroup.make(
            members: [original, companion].map {
                SplitMember.regularTab($0.id)
            },
            layoutKind: .vertical,
            container: .regularTabs(spaceId: fixture.space.id)
        ))
        XCTAssertTrue(
            fixture.tabManager.splitGroupMutations.insert(
                group,
                persist: false
            )
        )
        fixture.windowState.currentTabId = original.id
        fixture.windowState.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(original.id)
        )
        let prepared = try XCTUnwrap(
            makePresentationSynchronizer(fixture).prepareSettlement(
                previousGroups: [group],
                replacementGroups: fixture.tabManager.splitGroupStore.groups,
                affectedGroupIDs: [group.id],
                terminalParticipants: []
            )
        )
        let replacement = Tab(
            id: original.id,
            url: original.url,
            name: original.name,
            spaceId: fixture.space.id,
            index: original.index,
            loadsCachedFaviconOnInit: false
        )
        fixture.tabManager.structuralCollectionMutationOwner.setTabs(
            [replacement, companion],
            for: fixture.space.id
        )

        XCTAssertIdentical(
            fixture.tabManager.regularTabCollectionOwner.tab(for: original.id),
            replacement
        )
        XCTAssertFalse(prepared.stage())
    }

    func testLauncherMoveFailureLeavesGroupAndWindowsUntouched() throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            memberCount: 3,
            windowCount: 2,
            retirement: .accepting
        )
        let originalLiveTab = try XCTUnwrap(
            fixture.tabManager.liveShortcutTabs.tab(
                for: fixture.firstPin.id,
                in: fixture.windowState.id
            )
        )
        let secondWindow = fixture.windowStates[1]
        secondWindow.splitSelection = WindowSplitSelection(
            groupID: fixture.group.id,
            activeMemberID: .shortcutPin(fixture.secondPin.id)
        )
        let originalSelections = fixture.windowStates.map(\.splitSelection)
        var didRequestLauncherMove = false
        let failingPlacement = ShortcutSplitLauncherPlacementService(
            pins: fixture.tabManager.shortcutPinCollectionStateOwner,
            destinationResolver: ShortcutSplitLauncherDestinationResolver(
                folders: fixture.tabManager.folderCollectionStateOwner,
                spacePinnedStructure: fixture.tabManager
                    .spacePinnedStructureOwner
            ),
            moves: ShortcutSplitLauncherMoveTransaction(
                batches: TestShortcutSplitLauncherMoveBatchPreparer(
                    accepts: { _, _ in true },
                    prepare: { _ in
                        XCTFail("Unexpected standalone launcher preparation")
                        return nil
                    },
                    prepareForComposedResidenceAggregate: { _, _ in
                        didRequestLauncherMove = true
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
                folderOpenState: fixture.tabManager.folderOpenState
            )
        )
        let cancellable = observeStructure(in: fixture)

        XCTAssertFalse(makeMemberRestoreService(
            fixture,
            launcherPlacement: failingPlacement
        ).restoreShortcutSplitMember(
            .shortcutPin(fixture.firstPin.id),
            from: fixture.group,
            in: fixture.windowState,
            preserveLiveInstance: false
        ))

        XCTAssertEqual(
            fixture.tabManager.splitGroupStore.group(id: fixture.group.id),
            fixture.group
        )
        XCTAssertEqual(
            fixture.windowStates.map(\.splitSelection),
            originalSelections
        )
        XCTAssertEqual(fixture.probe.structuralEvents, 0)
        XCTAssertTrue(fixture.probe.eventsSeenAtUnload.isEmpty)
        XCTAssertEqual(fixture.probe.sessionWrites, 0)
        XCTAssertTrue(didRequestLauncherMove)
        XCTAssertIdentical(
            fixture.tabManager.liveShortcutTabs.tab(
                for: fixture.firstPin.id,
                in: fixture.windowState.id
            ),
            originalLiveTab
        )
        _ = cancellable
    }

    func testMemberRestoreHandsOffStandaloneMemberBeforeTeardown() throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            createsFallback: false,
            retirement: .accepting
        )

        makeMemberRestoreService(fixture).restoreShortcutSplitMember(
            .shortcutPin(fixture.firstPin.id),
            from: fixture.group,
            in: fixture.windowState,
            preserveLiveInstance: false
        )

        XCTAssertEqual(
            fixture.windowState.currentTabId,
            fixture.tabManager.liveShortcutTabs.tab(
                for: fixture.secondPin.id,
                in: fixture.windowState.id
            )?.id
        )
        XCTAssertFalse(fixture.windowState.isShowingEmptyState)
        XCTAssertEqual(fixture.probe.visualTeardownOrder, ["handoff", "unload"])
        XCTAssertNotNil(fixture.windowSessionSnapshotStore.loadSnapshot())
        XCTAssertEqual(
            fixture.tabManager.windowSessionPersistenceCoordinator.flush(),
            0
        )
    }

    func testHostedUnloadHandsOffEmptyStateBeforeTeardown() throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            createsFallback: false
        )

        makeHostedUnloadService(fixture).unloadShortcutHostedSplitGroup(
            fixture.group,
            in: fixture.windowState
        )

        XCTAssertNil(fixture.windowState.currentTabId)
        XCTAssertTrue(fixture.windowState.isShowingEmptyState)
        XCTAssertEqual(
            fixture.probe.visualTeardownOrder,
            ["handoff", "unload", "unload"]
        )
        XCTAssertEqual(fixture.probe.sessionWrites, 1)
    }

    func testCrossSpaceFocusQueueDoesNotWriteWindowSession() throws {
        let fixture = try makeFixture()
        fixture.windowState.currentSpaceId = UUID()

        makeFocusService(fixture).focusSplitGroup(
            fixture.group,
            in: fixture.windowState
        )

        XCTAssertEqual(
            fixture.windowState.presentationState.pendingSplitGroupFocusRequest?.groupID,
            fixture.group.id
        )
        XCTAssertEqual(fixture.probe.sessionWrites, 0)
    }

    func testLauncherPlacementRejectsCrossSpaceFolderDestination() throws {
        let spaceId = UUID()
        let folderId = UUID()
        let pin = try makePin(
            url: "https://placement.example",
            spaceId: spaceId,
            index: 0
        )
        var movedPin: ShortcutPin?
        var movedDestination: ShortcutSplitLauncherDestination?
        let pins = ShortcutPinCollectionStateOwner()
        pins.replaceSpacePinnedShortcuts([spaceId: [pin]])
        let resolverRuntime = BrowserManager()
        let foreignSpaceID = UUID()
        resolverRuntime.folderCollectionStateOwner.replaceFoldersBySpace([
            foreignSpaceID: [TabFolder(
                id: folderId,
                name: "Foreign",
                spaceId: foreignSpaceID
            )],
        ])
        let service = ShortcutSplitLauncherPlacementService(
            pins: pins,
            destinationResolver: ShortcutSplitLauncherDestinationResolver(
                folders: resolverRuntime.folderCollectionStateOwner,
                spacePinnedStructure: resolverRuntime
                    .spacePinnedStructureOwner
            ),
            moves: ShortcutSplitLauncherMoveTransaction(
                batches: TestShortcutSplitLauncherMoveBatchPreparer(
                    accepts: { _, _ in true },
                    prepare: { restorations in
                        movedPin = restorations.first?.pin
                        movedDestination = restorations.first?.destination
                        return TestShortcutSplitLauncherMoveBatchParticipant(
                            isCurrent: { true },
                            rollback: { true },
                            settle: {},
                            publish: {}
                        )
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
                ),
                windowMutations: BrowserWindowShortcutMutationOwner(),
                folderOpenState: BrowserManager().folderOpenState
            )
        )
        let member = SplitMember.shortcutPin(
            pin.id,
            returnPlacement: .spacePinned(
                spaceId: spaceId,
                folderId: folderId,
                index: 3
            )
        )

        let restorations = try XCTUnwrap(
            service.prepareRestorations(for: [member])
        )
        restorations.applyAndCommit()

        XCTAssertEqual(movedPin?.id, pin.id)
        XCTAssertEqual(movedDestination?.role, .spacePinned)
        XCTAssertEqual(movedDestination?.spaceId, spaceId)
        XCTAssertNil(movedDestination?.folderId)
        XCTAssertEqual(movedDestination?.index, 3)
    }

    func testLiveHostedUnloadWithoutFallbackEndsInEmptyState() throws {
        let windowSessionSnapshotStore = WindowSessionSnapshotStore(
            key: "SplitShortcutServicesTests.\(UUID().uuidString)",
            userDefaults: TestOwnedWindowSessionUserDefaults(),
            environment: { [:] }
        )
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            windowSessionSnapshotStore: windowSessionSnapshotStore
        )
        let registry = browserManager.windowRegistry
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        registry.register(windowState)
        let space = try XCTUnwrap(browserManager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: nil
        ))
        windowState.currentSpaceId = space.id
        let firstPin = try makePin(
            url: "https://first.example",
            spaceId: space.id,
            index: 0
        )
        let secondPin = try makePin(
            url: "https://second.example",
            spaceId: space.id,
            index: 1
        )
        browserManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([firstPin, secondPin], for: space.id)
        let group = try materializedGroup(
            tabManager: browserManager,
            windowState: windowState,
            pins: [firstPin, secondPin],
            spaceId: space.id
        )
        XCTAssertTrue(
            browserManager.splitGroupMutations.insert(
                group,
                persist: false
            )
        )
        let firstLive = try XCTUnwrap(
            browserManager.shortcutPresentationOwner
                .shortcutLiveTab(for: firstPin.id, in: windowState.id)
        )
        windowState.currentTabId = firstLive.id
        windowState.currentShortcutPinId = firstPin.id
        windowState.currentShortcutPinRole = .spacePinned
        windowState.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .shortcutPin(firstPin.id)
        )

        browserManager.splitShortcutHostedUnload
            .unloadShortcutHostedSplitGroup(group, in: windowState)

        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertTrue(windowState.isShowingEmptyState)
        XCTAssertTrue(
            browserManager.liveShortcutTabs
                .entries(for: firstPin.id).isEmpty
        )
        XCTAssertTrue(
            browserManager.liveShortcutTabs
                .entries(for: secondPin.id).isEmpty
        )
        _ = browserManager
    }

    func testFocusAndUnloadCommandsFailClosedWithoutRuntime() throws {
        let focusFixture = try makeFixture(materializeMembers: true)
        let originalSelection = focusFixture.windowState.splitSelection
        focusFixture.runtimeAttachment.detach()
        makeFocusService(focusFixture).focusSplitGroup(
            focusFixture.group,
            in: focusFixture.windowState
        )
        XCTAssertEqual(focusFixture.windowState.splitSelection, originalSelection)
        XCTAssertEqual(focusFixture.probe.sessionWrites, 0)

        let unloadFixture = try makeFixture(materializeMembers: true)
        unloadFixture.runtimeAttachment.detach()
        XCTAssertFalse(makeHostedUnloadService(unloadFixture)
            .unloadShortcutHostedSplitGroup(
                unloadFixture.group,
                in: unloadFixture.windowState
            ))
        XCTAssertEqual(
            unloadFixture.tabManager.splitGroupStore.group(
                id: unloadFixture.group.id
            ),
            unloadFixture.group
        )
    }

    func testRetainedSplitCommandsAndServicesReleaseRuntime() throws {
        let spaceId = UUID()
        let firstPin = try makePin(
            url: "https://late-first.example",
            spaceId: spaceId,
            index: 0
        )
        let secondPin = try makePin(
            url: "https://late-second.example",
            spaceId: spaceId,
            index: 1
        )
        let group = try proxyGroup(
            firstPin: firstPin,
            secondPin: secondPin,
            spaceId: spaceId
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = UUID()
        let originalTabId = UUID()
        windowState.currentTabId = originalTabId

        var browserManager: BrowserManager? = BrowserManager()
        weak let releasedBrowserManager = browserManager
        weak let releasedTabStateStore = browserManager?.tabStateStore
        weak let releasedSplitQuery = browserManager?.splitWindowContext.query
        let manager = try XCTUnwrap(browserManager)
        let windows = SidebarWindowIdentityQuery(
            registry: manager.shellRuntime.windowRegistry
        )
        let commands = SidebarSplitFocusCommands(
            focus: manager.splitShortcutFocus,
            restoration: manager.splitShortcutMemberRestoration,
            groups: manager.splitGroupStore,
            windows: windows
        )
        let retainedHostedUnload = try XCTUnwrap(browserManager)
            .splitShortcutHostedUnload

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNil(releasedTabStateStore)
        XCTAssertNil(releasedSplitQuery)
        commands.focusGroup(group.id, nil, windowState.id)
        commands.restoreMember(
            group.id,
            .shortcutPin(firstPin.id),
            windowState.id
        )
        XCTAssertFalse(
            retainedHostedUnload.unloadShortcutHostedSplitGroup(
                group,
                in: windowState
            )
        )
        XCTAssertNil(windowState.presentationState.pendingSplitGroupFocusRequest)
        XCTAssertEqual(windowState.currentTabId, originalTabId)
        XCTAssertFalse(windowState.isShowingEmptyState)
        withExtendedLifetime(retainedHostedUnload) {}
    }
}

@MainActor
private extension SplitShortcutServicesTests {
    func makeFixture(
        materializeMembers: Bool = false,
        createsFallback: Bool = true,
        memberCount: Int = 2,
        windowCount: Int = 1,
        retirement: TestRuntimePorts.RetirementCapabilities = .rejecting
    ) throws -> SplitServiceFixture {
        precondition((2...4).contains(memberCount))
        precondition(windowCount > 0)
        let windowSessionSnapshotStore = WindowSessionSnapshotStore(
            key: "SplitShortcutServicesTests.\(UUID().uuidString)",
            userDefaults: TestOwnedWindowSessionUserDefaults(),
            environment: { [:] }
        )
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            ),
            windowSessionSnapshotStore: windowSessionSnapshotStore
        )
        let tabManager = browserManager
        let runtimeAttachment = tabManager.runtimePortConnection
        let profile = Profile(name: "Split service fixture")
        let space = try XCTUnwrap(tabManager.sidebarSpaceLifecycle.createSpace(
            name: "Space",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profile.id
        ))
        let fallback = createsFallback
            ? tabManager.regularTabLifecycleOwner.createNewTab(
                url: "https://fallback.example",
                in: space,
                activate: false
            )
            : nil
        let pins = try (0..<memberCount).map { index in
            try makePin(
                url: "https://split-member-\(index).example",
                spaceId: space.id,
                index: index
            )
        }
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts(pins, for: space.id)
        let windowStates = (0..<windowCount).map { _ in
            let windowState = BrowserWindowState()
            windowState.currentSpaceId = space.id
            return windowState
        }
        windowStates.forEach { browserManager.windowRegistry.register($0) }
        let windowState = windowStates[0]
        let probe = SplitServiceProbe()
        attachRuntime(
            to: tabManager,
            attachment: runtimeAttachment,
            windowStates: windowStates,
            probe: probe,
            retirement: retirement,
            profile: profile
        )
        let group = materializeMembers
            ? try materializedGroup(
                tabManager: tabManager,
                windowState: windowState,
                pins: pins,
                spaceId: space.id
            )
            : try proxyGroup(
                pins: pins,
                spaceId: space.id
            )
        XCTAssertTrue(
            tabManager.splitGroupMutations.insert(group, persist: false)
        )
        if materializeMembers {
            let firstLive = try XCTUnwrap(
                tabManager.shortcutPresentationOwner.shortcutLiveTab(
                    for: pins[0].id,
                    in: windowState.id
                )
            )
            windowState.currentTabId = firstLive.id
            windowState.currentShortcutPinId = pins[0].id
            windowState.currentShortcutPinRole = .spacePinned
            windowState.splitSelection = WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .shortcutPin(pins[0].id)
            )
        }
        return SplitServiceFixture(
            browserManager: browserManager,
            space: space,
            fallback: fallback,
            pins: pins,
            windowStates: windowStates,
            group: group,
            probe: probe,
            runtimeAttachment: runtimeAttachment,
            windowSessionSnapshotStore: windowSessionSnapshotStore
        )
    }

    func attachRuntime(
        to tabManager: BrowserManager,
        attachment: TabRuntimePortConnection,
        windowStates: [BrowserWindowState],
        probe: SplitServiceProbe,
        retirement: TestRuntimePorts.RetirementCapabilities,
        profile: Profile
    ) {
        let windowsByID = Dictionary(
            uniqueKeysWithValues: windowStates.map { ($0.id, $0) }
        )
        attachment.detach()
        attachment.attach(
            TestRuntimePorts.make(
                defaultProfileId: { profile.id },
                profile: { $0 == profile.id ? profile : nil },
                windowState: { windowsByID[$0] },
                windows: { windowStates.map { ($0.id, $0) } },
                windowStates: { windowStates },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                    retirement: retirement,
                    unloadTab: { _ in
                        probe.visualTeardownOrder.append("unload")
                        probe.eventsSeenAtUnload.append(
                            probe.structuralEvents
                        )
                    }
                ),
                persistWindowSession: { _ in probe.sessionWrites += 1 }
            )
        )
    }

    func materializedGroup(
        tabManager: BrowserManager,
        windowState: BrowserWindowState,
        pins: [ShortcutPin],
        spaceId: UUID
    ) throws -> SplitGroup {
        for pin in pins {
            _ = tabManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowState.id,
                currentSpaceId: spaceId
            )!
        }
        return try proxyGroup(
            pins: pins,
            spaceId: spaceId
        )
    }

    func proxyGroup(
        firstPin: ShortcutPin,
        secondPin: ShortcutPin,
        spaceId: UUID
    ) throws -> SplitGroup {
        try proxyGroup(pins: [firstPin, secondPin], spaceId: spaceId)
    }

    func proxyGroup(
        pins: [ShortcutPin],
        spaceId: UUID
    ) throws -> SplitGroup {
        try XCTUnwrap(
            SplitGroup.make(
                members: pins.enumerated().map { index, pin in
                    splitMember(pin, spaceId: spaceId, index: index)
                },
                layoutKind: .vertical,
                container: .shortcutSidebar(
                    spaceId: spaceId,
                    profileId: nil,
                    folderId: nil,
                    index: 0
                )
            )
        )
    }

    func splitMember(
        _ pin: ShortcutPin,
        spaceId: UUID,
        index: Int
    ) -> SplitMember {
        SplitMember.shortcutPin(
            pin.id,
            returnPlacement: .spacePinned(
                spaceId: spaceId,
                folderId: nil,
                index: index
            )
        )
    }

    func makeFocusService(
        _ fixture: SplitServiceFixture
    ) -> SplitShortcutFocusService {
        let tabs = fixture.tabManager
        return SplitShortcutFocusService(
            runtimeConnection: tabs.runtimePortConnection,
            splitGroups: tabs.splitGroupStore,
            materialization: WindowSplitMaterializationService(
                query: WindowSplitMaterializationQuery(
                    splitGroups: tabs.splitGroupStore,
                    regularTabs: tabs.regularTabCollectionOwner,
                    pins: tabs.shortcutPinCollectionStateOwner,
                    liveShortcuts: tabs.liveShortcutTabs
                ),
                activation: tabs.shortcutPresentationActivation,
                structuralLookup: tabs.structuralLookupCoordinator
            ),
            presentation: SplitShortcutFocusPresentationService(
                selection: fixture.browserManager.browserTabSelection,
                visuals: makeVisuals(fixture),
                persistence: makeWindowPersistence(fixture)
            )
        )
    }

    func makeMemberRestoreService(
        _ fixture: SplitServiceFixture,
        launcherPlacement: ShortcutSplitLauncherPlacementService? = nil
    ) -> SplitShortcutMemberRestoreService {
        SplitShortcutMemberRestoreService(
            preparation: SplitShortcutMemberRestorePreparationService(
                splitGroups: fixture.tabManager.splitGroupStore,
                pins: fixture.tabManager.shortcutPinCollectionStateOwner,
                liveShortcuts: fixture.tabManager.liveShortcutTabs,
                runtimeConnection: fixture.tabManager.runtimePortConnection,
                launcherPlacement: launcherPlacement
                    ?? makeLauncherPlacementService(fixture)
            ),
            splitMutations: fixture.tabManager.splitGroupMutations,
            shortcutRetirement: fixture.tabManager.shortcutLiveTabRetirement,
            publication: SplitShortcutMemberRestorePublication(
                presentations: makePresentationSynchronizer(fixture),
                folderOpenState: fixture.tabManager.folderOpenState,
                visuals: makeVisuals(fixture)
            )
        )
    }

    func makePresentationSynchronizer(
        _ fixture: SplitServiceFixture
    ) -> WindowSplitPresentationSynchronizer {
        makeTestWindowSplitPresentationSynchronizer(
            browser: fixture.tabManager,
            windows: { fixture.windowStates }
        )
    }

    func makeLauncherPlacementService(
        _ fixture: SplitServiceFixture
    ) -> ShortcutSplitLauncherPlacementService {
        makeTestShortcutSplitLauncherPlacement(fixture.tabManager)
    }

    func makeHostedUnloadService(
        _ fixture: SplitServiceFixture
    ) -> ShortcutHostedSplitUnloadService {
        let tabs = fixture.tabManager
        return ShortcutHostedSplitUnloadService(
            runtimeConnection: tabs.runtimePortConnection,
            splitGroups: tabs.splitGroupStore,
            retirement: tabs.shortcutLiveTabRetirement,
            fallback: ShortcutHostedSplitFallbackQuery(
                spaces: tabs.spaceStateOwner,
                regularTabs: tabs.regularTabCollectionOwner
            ),
            visuals: makeVisuals(fixture)
        )
    }

    func makeVisuals(
        _ fixture: SplitServiceFixture,
        handoff: ((BrowserWindowState) -> Void)? = nil
    ) -> BrowserWindowVisualCoordinator {
        for windowState in fixture.windowStates {
            fixture.browserManager.webViewRuntime.compositorRuntime.registerContainer(
                NSView(),
                for: windowState.id,
                immediateVisualHandoffHandler: {
                    if let handoff {
                        handoff(windowState)
                    } else {
                        fixture.probe.visualTeardownOrder.append("handoff")
                    }
                    return true
                }
            )
        }
        return fixture.browserManager.shellRuntime.windowVisuals
    }

    func makeWindowPersistence(
        _ fixture: SplitServiceFixture
    ) -> WindowSessionPersistenceCoordinator {
        let runtime = fixture.browserManager.windowSessionPersistence
        return WindowSessionPersistenceTestComposition(
            snapshotStore: runtime.snapshotStore,
            scheduler: runtime.scheduler,
            snapshotFactory: WindowSessionSnapshotFactory(
                glanceManager: fixture.browserManager.glanceManager
            ),
            windows: fixture.browserManager.windowRegistry
        ).coordinator
    }

    func observeStructure(
        in fixture: SplitServiceFixture
    ) -> AnyCancellable {
        let cancellable = fixture.tabManager.tabStructureEventBus
            .structureChangedPublisher.sink {
                fixture.probe.structuralEvents += 1
            }
        fixture.probe.structuralEvents = 0
        return cancellable
    }

    static func applySelection(_ tab: Tab, to windowState: BrowserWindowState) {
        _ = WindowTabSelectionStateApplicator.apply(
            tab,
            to: windowState,
            updateSpaceFromTab: true,
            rememberSelection: true
        )
    }

    func showEmptyState(_ windowState: BrowserWindowState) {
        windowState.currentTabId = nil
        windowState.currentShortcutPinId = nil
        windowState.currentShortcutPinRole = nil
        windowState.isShowingEmptyState = true
    }

    func makePin(
        url: String,
        spaceId: UUID,
        index: Int
    ) throws -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: index,
            launchURL: try XCTUnwrap(URL(string: url)),
            title: url
        )
    }

    func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}

@MainActor
private struct SplitServiceFixture {
    let browserManager: BrowserManager
    let space: Space
    let fallback: Tab?
    let pins: [ShortcutPin]
    let windowStates: [BrowserWindowState]
    let group: SplitGroup
    let probe: SplitServiceProbe
    let runtimeAttachment: TabRuntimePortConnection
    let windowSessionSnapshotStore: WindowSessionSnapshotStore

    var tabManager: BrowserManager { browserManager }
    var firstPin: ShortcutPin { pins[0] }
    var secondPin: ShortcutPin { pins[1] }
    var windowState: BrowserWindowState { windowStates[0] }
}

@MainActor
private final class SplitTerminalObservationOracle {
    var sawTerminalState = false
    var reentrantGroup: SplitGroup?
}

private final class SplitServiceProbe {
    var structuralEvents = 0
    var eventsSeenAtUnload: [Int] = []
    var sessionWrites = 0
    var visualTeardownOrder: [String] = []
}
