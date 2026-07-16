import Combine
import Observation
import SumiDomain
import SwiftData
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SplitShortcutServicesTests: XCTestCase {
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
                fixture.tabManager.runtimePortsAttachmentOwner.detach()
                fixture.tabManager.runtimePortsAttachmentOwner.attach(runtime)
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
        runtime = fixture.tabManager.requireRuntimePorts()
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
        let unrelatedSpace = fixture.tabManager.spaceServices.catalog
            .createSpace(name: "Unrelated")
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
        XCTAssertEqual(fixture.probe.sessionWrites, 2)
        XCTAssertEqual(fixture.probe.immediateSessionWrites, 2)
        XCTAssertEqual(fixture.probe.scheduledSessionWrites, 0)
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
        XCTAssertEqual(fixture.probe.sessionWrites, 2)
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
        let folder = fixture.tabManager.folderMutationOwner.createFolder(
            for: fixture.space.id,
            name: "Restored"
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
        let presentations = WindowSplitPresentationSynchronizer(
            tabManager: { fixture.tabManager },
            windows: { currentWindows },
            selectTabWithoutPersistence: { _, _ in },
            publishPreparedSelectionEffects: { _, _, _, _ in },
            publishWindowChange: { _ in },
            refreshCompositor: { _ in },
            scheduleWindowSession: { _ in },
            persistWindowSession: { _ in }
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
        let presentations = WindowSplitPresentationSynchronizer(
            tabManager: { fixture.tabManager },
            windows: { [replacement] },
            selectTabWithoutPersistence: { _, _ in },
            publishPreparedSelectionEffects: { _, _, _, _ in },
            publishWindowChange: { _ in },
            refreshCompositor: { _ in },
            scheduleWindowSession: { _ in },
            persistWindowSession: { _ in }
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

    func testTerminalWindowABASkipsStaleCompositorSessionAndHandoff()
        throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            memberCount: 3
        )
        var currentWindows = fixture.windowStates
        let replacement = BrowserWindowState(id: fixture.windowState.id)
        var preparedSelectionEffectCount = 0
        var windowChangeCount = 0
        var compositorCount = 0
        var sessionWriteCount = 0
        var handoffCount = 0
        let presentations = WindowSplitPresentationSynchronizer(
            tabManager: { fixture.tabManager },
            windows: { currentWindows },
            selectTabWithoutPersistence: { tab, window in
                Self.applySelection(tab, to: window)
            },
            publishPreparedSelectionEffects: { _, window, _, _ in
                XCTAssertIdentical(window, fixture.windowState)
                preparedSelectionEffectCount += 1
                currentWindows = [replacement]
            },
            publishWindowChange: { _ in windowChangeCount += 1 },
            refreshCompositor: { _ in compositorCount += 1 },
            scheduleWindowSession: { _ in sessionWriteCount += 1 },
            persistWindowSession: { _ in sessionWriteCount += 1 }
        )
        let service = SplitShortcutMemberRestoreService(
            runtimeLease: makeRuntimeLease(fixture),
            launcherPlacement: makeLauncherPlacementService(fixture),
            presentations: presentations,
            performImmediateVisualHandoff: { _ in handoffCount += 1 }
        )

        XCTAssertTrue(service.restoreShortcutSplitMember(
            .shortcutPin(fixture.firstPin.id),
            from: fixture.group,
            in: fixture.windowState
        ))

        XCTAssertEqual(preparedSelectionEffectCount, 1)
        XCTAssertEqual(windowChangeCount, 0)
        XCTAssertEqual(compositorCount, 0)
        XCTAssertEqual(sessionWriteCount, 0)
        XCTAssertEqual(handoffCount, 0)
        XCTAssertNil(replacement.currentTabId)
        XCTAssertNil(replacement.splitSelection)
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
        let shortcutPin: (UUID) -> ShortcutPin? = { pinID in
            fixture.tabManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: pinID)
        }
        var didRequestLauncherMove = false
        let failingPlacement = ShortcutSplitLauncherPlacementService(
            shortcutPin: shortcutPin,
            destinationResolver: ShortcutSplitLauncherDestinationResolver(
                folderSpaceID: { _ in nil },
                topLevelItemCount: { _ in 0 }
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
        XCTAssertEqual(fixture.probe.sessionWrites, 1)
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
        let shortcutPin: (UUID) -> ShortcutPin? = {
            $0 == pin.id ? pin : nil
        }
        let service = ShortcutSplitLauncherPlacementService(
            shortcutPin: shortcutPin,
            destinationResolver: ShortcutSplitLauncherDestinationResolver(
                folderSpaceID: { $0 == folderId ? UUID() : nil },
                topLevelItemCount: { _ in 0 }
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
                folderOpenState: try makeInMemoryTabManager().folderOpenState
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
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let registry = WindowRegistry()
        browserManager.windowRegistry = registry
        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        registry.register(windowState)
        let space = browserManager.tabManager.spaceServices.catalog
            .createSpace(name: "Space")
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
        browserManager.tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([firstPin, secondPin], for: space.id)
        let group = try materializedGroup(
            tabManager: browserManager.tabManager,
            windowState: windowState,
            pins: [firstPin, secondPin],
            spaceId: space.id
        )
        XCTAssertTrue(
            browserManager.tabManager.splitGroupMutations.insert(
                group,
                persist: false
            )
        )
        let firstLive = try XCTUnwrap(
            browserManager.tabManager.shortcutPresentationOwner
                .shortcutLiveTab(for: firstPin.id, in: windowState.id)
        )
        windowState.currentTabId = firstLive.id
        windowState.currentShortcutPinId = firstPin.id
        windowState.currentShortcutPinRole = .spacePinned
        windowState.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .shortcutPin(firstPin.id)
        )

        browserManager.sidebarCommandService.splitShortcuts.hostedUnload
            .unloadShortcutHostedSplitGroup(group, in: windowState)

        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertTrue(windowState.isShowingEmptyState)
        XCTAssertTrue(
            browserManager.tabManager.liveShortcutTabs
                .entries(for: firstPin.id).isEmpty
        )
        XCTAssertTrue(
            browserManager.tabManager.liveShortcutTabs
                .entries(for: secondPin.id).isEmpty
        )
        _ = browserManager
    }

    func testEachTopLevelCommandAcquiresOneRuntimeLease() throws {
        let focusFixture = try makeFixture()
        var focusLeaseCount = 0
        let focusLease = makeRuntimeLease(focusFixture)
        makeFocusService(focusFixture, runtimeLease: {
            focusLeaseCount += 1
            return focusLease()
        }).focusSplitGroup(focusFixture.group, in: focusFixture.windowState)
        XCTAssertEqual(focusLeaseCount, 1)

        let restoreFixture = try makeFixture()
        var restoreLeaseCount = 0
        let restoreLease = makeRuntimeLease(restoreFixture)
        makeMemberRestoreService(restoreFixture, runtimeLease: {
            restoreLeaseCount += 1
            return restoreLease()
        }).restoreShortcutSplitMember(
            .shortcutPin(restoreFixture.firstPin.id),
            from: restoreFixture.group,
            in: restoreFixture.windowState
        )
        XCTAssertEqual(restoreLeaseCount, 1)

        let unloadFixture = try makeFixture()
        var unloadLeaseCount = 0
        let unloadLease = makeRuntimeLease(unloadFixture)
        makeHostedUnloadService(unloadFixture, runtimeLease: {
            unloadLeaseCount += 1
            return unloadLease()
        }).unloadShortcutHostedSplitGroup(
            unloadFixture.group,
            in: unloadFixture.windowState
        )
        XCTAssertEqual(unloadLeaseCount, 1)
    }

    func testRetainedCommandActionsAndSplitServicesReleaseRuntime() throws {
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
        weak let releasedTabManager = browserManager?.tabManager
        weak let releasedSplitQuery = browserManager?.splitComposition.query
        let actions = try XCTUnwrap(browserManager)
            .sidebarCommandService.makeCommandActions()
        let retainedServices = try XCTUnwrap(browserManager)
            .sidebarCommandService.splitShortcuts

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNil(releasedTabManager)
        XCTAssertNil(releasedSplitQuery)
        actions.focusSplitGroup(group.id, nil, windowState.id)
        actions.restoreShortcutSplitMember(
            group.id,
            .shortcutPin(firstPin.id),
            windowState.id
        )
        XCTAssertFalse(
            retainedServices.hostedUnload.unloadShortcutHostedSplitGroup(
                group,
                in: windowState
            )
        )
        XCTAssertNil(windowState.presentationState.pendingSplitGroupFocusRequest)
        XCTAssertEqual(windowState.currentTabId, originalTabId)
        XCTAssertFalse(windowState.isShowingEmptyState)
        withExtendedLifetime(retainedServices) {
            // Proves the complete service group is harmless after teardown.
        }
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
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let tabManager = browserManager.tabManager
        let profile = Profile(name: "Split service fixture")
        let space = tabManager.spaceServices.catalog.createSpace(
            name: "Space",
            profileId: profile.id
        )
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
        let windowState = windowStates[0]
        let probe = SplitServiceProbe()
        attachRuntime(
            to: tabManager,
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
            probe: probe
        )
    }

    func attachRuntime(
        to tabManager: TabManager,
        windowStates: [BrowserWindowState],
        probe: SplitServiceProbe,
        retirement: TestRuntimePorts.RetirementCapabilities,
        profile: Profile
    ) {
        let windowsByID = Dictionary(
            uniqueKeysWithValues: windowStates.map { ($0.id, $0) }
        )
        tabManager.runtimePortsAttachmentOwner.detach()
        tabManager.runtimePortsAttachmentOwner.attach(
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
        tabManager: TabManager,
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
        _ fixture: SplitServiceFixture,
        runtimeLease: (() -> SplitShortcutRuntimeLease?)? = nil
    ) -> SplitShortcutFocusService {
        SplitShortcutFocusService(
            runtimeLease: runtimeLease ?? makeRuntimeLease(fixture),
            selectTabWithoutPersistence: { tab, windowState in
                Self.applySelection(tab, to: windowState)
            },
            refreshCompositor: { _ in /* No-op. */ },
            persistWindowSession: { _ in fixture.probe.sessionWrites += 1 }
        )
    }

    func makeMemberRestoreService(
        _ fixture: SplitServiceFixture,
        runtimeLease: (() -> SplitShortcutRuntimeLease?)? = nil,
        launcherPlacement: ShortcutSplitLauncherPlacementService? = nil
    ) -> SplitShortcutMemberRestoreService {
        SplitShortcutMemberRestoreService(
            runtimeLease: runtimeLease ?? makeRuntimeLease(fixture),
            launcherPlacement: launcherPlacement
                ?? makeLauncherPlacementService(fixture),
            presentations: makePresentationSynchronizer(fixture),
            performImmediateVisualHandoff: { _ in
                fixture.probe.visualTeardownOrder.append("handoff")
            }
        )
    }

    func makePresentationSynchronizer(
        _ fixture: SplitServiceFixture
    ) -> WindowSplitPresentationSynchronizer {
        WindowSplitPresentationSynchronizer(
            tabManager: { fixture.tabManager },
            windows: { fixture.windowStates },
            selectTabWithoutPersistence: { tab, windowState in
                Self.applySelection(tab, to: windowState)
            },
            publishPreparedSelectionEffects: { _, _, _, _ in
                /* Fixture records model selection separately. */
            },
            publishWindowChange: { _ in
                /* Individual tests install a publisher when it matters. */
            },
            refreshCompositor: { _ in /* No-op. */ },
            scheduleWindowSession: { _ in
                fixture.probe.sessionWrites += 1
                fixture.probe.scheduledSessionWrites += 1
            },
            persistWindowSession: { _ in
                fixture.probe.sessionWrites += 1
                fixture.probe.immediateSessionWrites += 1
            }
        )
    }

    func makeLauncherPlacementService(
        _ fixture: SplitServiceFixture
    ) -> ShortcutSplitLauncherPlacementService {
        ShortcutSplitLauncherPlacementService(
            tabManager: fixture.tabManager
        )
    }

    func makeHostedUnloadService(
        _ fixture: SplitServiceFixture,
        runtimeLease: (() -> SplitShortcutRuntimeLease?)? = nil
    ) -> ShortcutHostedSplitUnloadService {
        ShortcutHostedSplitUnloadService(
            runtimeLease: runtimeLease ?? makeRuntimeLease(fixture),
            performImmediateVisualHandoff: { _ in
                fixture.probe.visualTeardownOrder.append("handoff")
            },
            refreshCompositor: { _ in /* No-op. */ }
        )
    }

    func makeRuntimeLease(
        _ fixture: SplitServiceFixture
    ) -> () -> SplitShortcutRuntimeLease? {
        weak let tabManager = fixture.tabManager
        return {
            guard let tabManager else { return nil }
            return SplitShortcutRuntimeLease(tabManager: tabManager)
        }
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

    var tabManager: TabManager { browserManager.tabManager }
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
    var scheduledSessionWrites = 0
    var immediateSessionWrites = 0
    var visualTeardownOrder: [String] = []
}
