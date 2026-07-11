import Combine
import SumiDomain
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SplitShortcutServicesTests: XCTestCase {
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
            windowCount: 2
        )
        let secondWindow = fixture.windowStates[1]
        secondWindow.splitSelection = WindowSplitSelection(
            groupID: fixture.group.id,
            activeMemberID: .shortcutPin(fixture.secondPin.id)
        )
        let cancellable = observeStructure(in: fixture)

        XCTAssertTrue(makeMemberRestoreService(fixture).restoreShortcutSplitMember(
            .shortcutPin(fixture.firstPin.id),
            from: fixture.group,
            in: fixture.windowState,
            preserveLiveInstance: false
        ))

        // One durable-group commit plus the second window's required runtime
        // materialization must both publish before the retiring tab unloads.
        XCTAssertEqual(fixture.probe.structuralEvents, 2)
        XCTAssertEqual(fixture.probe.eventsSeenAtUnload, [2])
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
            windowCount: 2
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

    func testLauncherMoveFailureLeavesGroupAndWindowsUntouched() throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            memberCount: 3,
            windowCount: 2
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
        let failingPlacement = ShortcutSplitLauncherPlacementService(
            shortcutPin: shortcutPin,
            destinationResolver: ShortcutSplitLauncherDestinationResolver(
                folderSpaceID: { _ in nil },
                topLevelItemCount: { _ in 0 }
            ),
            moves: ShortcutSplitLauncherMoveTransaction(
                shortcutPin: shortcutPin,
                canMove: { _, _ in true },
                move: { _, _ in nil }
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
        _ = cancellable
    }

    func testMemberRestoreHandsOffStandaloneMemberBeforeTeardown() throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            createsFallback: false
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
            fixture.windowState.pendingSplitGroupFocusRequest?.groupID,
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
                shortcutPin: shortcutPin,
                canMove: { _, _ in true },
                move: {
                    movedPin = $0
                    movedDestination = $1
                    return $0
                }
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

        let restoration = try XCTUnwrap(
            service.prepareRestoration(for: member)
        )
        service.apply(restoration)

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
        browserManager.bindTestWebViewCoordinator()
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
        XCTAssertNil(windowState.pendingSplitGroupFocusRequest)
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
        windowCount: Int = 1
    ) throws -> SplitServiceFixture {
        precondition((2...4).contains(memberCount))
        precondition(windowCount > 0)
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
        let tabManager = browserManager.tabManager
        let space = tabManager.spaceServices.catalog.createSpace(name: "Space")
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
            probe: probe
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
        probe: SplitServiceProbe
    ) {
        let windowsByID = Dictionary(
            uniqueKeysWithValues: windowStates.map { ($0.id, $0) }
        )
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                windowState: { windowsByID[$0] },
                windows: { windowStates.map { ($0.id, $0) } },
                windowStates: { windowStates },
                webViewLifecycle: TestRuntimePorts.webViewLifecycle(
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
            )
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
            selectTabWithoutPersistence: applySelection,
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
            selectTabWithoutPersistence: applySelection,
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
            tabManager: { fixture.tabManager }
        )
    }

    func makeHostedUnloadService(
        _ fixture: SplitServiceFixture,
        runtimeLease: (() -> SplitShortcutRuntimeLease?)? = nil
    ) -> ShortcutHostedSplitUnloadService {
        ShortcutHostedSplitUnloadService(
            runtimeLease: runtimeLease ?? makeRuntimeLease(fixture),
            selectTabWithoutPersistence: applySelection,
            showEmptyStateWithoutPersistence: showEmptyState,
            performImmediateVisualHandoff: { _ in
                fixture.probe.visualTeardownOrder.append("handoff")
            },
            refreshCompositor: { _ in /* No-op. */ },
            persistWindowSession: { _ in fixture.probe.sessionWrites += 1 }
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

    func applySelection(_ tab: Tab, to windowState: BrowserWindowState) {
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

private final class SplitServiceProbe {
    var structuralEvents = 0
    var eventsSeenAtUnload: [Int] = []
    var sessionWrites = 0
    var scheduledSessionWrites = 0
    var immediateSessionWrites = 0
    var visualTeardownOrder: [String] = []
}
