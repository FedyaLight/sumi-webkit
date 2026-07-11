import Combine
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
        fixture.windowState.currentTabId = fixture.group.tabIds.first
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

    func testHostedUnloadPublishesProxyBeforeTeardown() throws {
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
        let proxyGroup = try XCTUnwrap(
            fixture.tabManager.splitGroupCollectionStateOwner
                .group(with: fixture.group.id)
        )
        XCTAssertEqual(
            proxyGroup.tabIds,
            [fixture.firstPin.id, fixture.secondPin.id]
        )
        XCTAssertEqual(proxyGroup.activeTabId, fixture.firstPin.id)
        XCTAssertEqual(fixture.probe.sessionWrites, 1)
        _ = cancellable
    }

    func testRestoreClosingMemberPublishesBeforeTeardown() throws {
        let fixture = try makeFixture(materializeMembers: true)
        let cancellable = observeStructure(in: fixture)

        makeMemberRestoreService(fixture).restoreShortcutSplitMember(
            fixture.group.tabIds[0],
            from: fixture.group,
            in: fixture.windowState,
            preserveLiveInstance: false
        )

        XCTAssertEqual(fixture.probe.structuralEvents, 1)
        XCTAssertEqual(fixture.probe.eventsSeenAtUnload, [1])
        XCTAssertEqual(
            fixture.windowState.currentTabId,
            try XCTUnwrap(fixture.fallback).id
        )
        XCTAssertTrue(
            fixture.tabManager.liveShortcutTabs
                .entries(for: fixture.firstPin.id).isEmpty
        )
        XCTAssertEqual(
            fixture.tabManager.liveShortcutTabs
                .entries(for: fixture.secondPin.id).count,
            1
        )
        XCTAssertNil(
            fixture.tabManager.splitGroupCollectionStateOwner
                .group(with: fixture.group.id)
        )
        XCTAssertEqual(fixture.probe.sessionWrites, 1)
        _ = cancellable
    }

    func testMemberRestoreHandsOffEmptyStateBeforeTeardown() throws {
        let fixture = try makeFixture(
            materializeMembers: true,
            createsFallback: false
        )

        makeMemberRestoreService(fixture).restoreShortcutSplitMember(
            fixture.group.tabIds[0],
            from: fixture.group,
            in: fixture.windowState,
            preserveLiveInstance: false
        )

        XCTAssertNil(fixture.windowState.currentTabId)
        XCTAssertTrue(fixture.windowState.isShowingEmptyState)
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
            fixture.windowState.pendingSplitGroupFocusRequest?.groupId,
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
        let service = ShortcutSplitLauncherPlacementService(
            shortcutPin: { $0 == pin.id ? pin : nil },
            folderSpaceId: { $0 == folderId ? UUID() : nil },
            topLevelItemCount: { _ in 0 },
            moveShortcut: {
                movedPin = $0
                movedDestination = $1
            }
        )
        let member = SplitGroupMember(
            tabId: pin.id,
            pinId: pin.id,
            origin: .spacePinned(
                spaceId: spaceId,
                folderId: folderId,
                index: 3
            )
        )

        service.restore(member)

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
            firstPin: firstPin,
            secondPin: secondPin,
            spaceId: space.id
        )
        windowState.currentTabId = group.tabIds[0]
        windowState.currentShortcutPinId = firstPin.id
        windowState.currentShortcutPinRole = .spacePinned

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
            restoreFixture.firstPin.id,
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
        weak let releasedSplitManager = browserManager?.splitManager
        let actions = try XCTUnwrap(browserManager)
            .sidebarCommandService.makeCommandActions()
        let retainedServices = try XCTUnwrap(browserManager)
            .sidebarCommandService.splitShortcuts

        browserManager = nil

        XCTAssertNil(releasedBrowserManager)
        XCTAssertNil(releasedTabManager)
        XCTAssertNil(releasedSplitManager)
        actions.focusSplitGroup(group, windowState)
        actions.restoreShortcutSplitMember(firstPin.id, group, windowState)
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
        createsFallback: Bool = true
    ) throws -> SplitServiceFixture {
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
        tabManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([firstPin, secondPin], for: space.id)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        let probe = SplitServiceProbe()
        attachRuntime(
            to: tabManager,
            windowState: windowState,
            probe: probe
        )
        let group = materializeMembers
            ? try materializedGroup(
                tabManager: tabManager,
                windowState: windowState,
                firstPin: firstPin,
                secondPin: secondPin,
                spaceId: space.id
            )
            : try proxyGroup(
                firstPin: firstPin,
                secondPin: secondPin,
                spaceId: space.id
            )
        tabManager.splitGroupStructureOwner.upsertSplitGroup(
            group,
            schedulePersistence: false
        )
        if materializeMembers {
            windowState.currentTabId = group.tabIds[0]
            windowState.currentShortcutPinId = firstPin.id
            windowState.currentShortcutPinRole = .spacePinned
        }
        return SplitServiceFixture(
            browserManager: browserManager,
            space: space,
            fallback: fallback,
            firstPin: firstPin,
            secondPin: secondPin,
            windowState: windowState,
            group: group,
            probe: probe
        )
    }

    func attachRuntime(
        to tabManager: TabManager,
        windowState: BrowserWindowState,
        probe: SplitServiceProbe
    ) {
        tabManager.runtimePortsAttachmentOwner.attach(
            TestRuntimePorts.make(
                windowState: { $0 == windowState.id ? windowState : nil },
                windows: { [(windowState.id, windowState)] },
                windowStates: { [windowState] },
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
        firstPin: ShortcutPin,
        secondPin: ShortcutPin,
        spaceId: UUID
    ) throws -> SplitGroup {
        let firstLive = tabManager.shortcutTabMaterializer.materialize(
            firstPin,
            in: windowState.id,
            currentSpaceId: spaceId
        )
        let secondLive = tabManager.shortcutTabMaterializer.materialize(
            secondPin,
            in: windowState.id,
            currentSpaceId: spaceId
        )
        return try XCTUnwrap(
            SplitGroup.make(
                tabIds: [firstLive.id, secondLive.id],
                layoutKind: .vertical,
                host: .shortcutPinned(
                    spaceId: spaceId,
                    profileId: nil,
                    index: 0
                ),
                members: [
                    splitMember(firstLive, pin: firstPin, spaceId: spaceId, index: 0),
                    splitMember(secondLive, pin: secondPin, spaceId: spaceId, index: 1),
                ]
            )
        )
    }

    func proxyGroup(
        firstPin: ShortcutPin,
        secondPin: ShortcutPin,
        spaceId: UUID
    ) throws -> SplitGroup {
        try XCTUnwrap(
            SplitGroup.make(
                tabIds: [firstPin.id, secondPin.id],
                layoutKind: .vertical,
                host: .shortcutPinned(
                    spaceId: spaceId,
                    profileId: nil,
                    index: 0
                ),
                members: [
                    splitMember(firstPin, spaceId: spaceId, index: 0),
                    splitMember(secondPin, spaceId: spaceId, index: 1),
                ]
            )
        )
    }

    func splitMember(
        _ tab: Tab,
        pin: ShortcutPin,
        spaceId: UUID,
        index: Int
    ) -> SplitGroupMember {
        SplitGroupMember(
            tabId: tab.id,
            pinId: pin.id,
            origin: .spacePinned(
                spaceId: spaceId,
                folderId: nil,
                index: index
            )
        )
    }

    func splitMember(
        _ pin: ShortcutPin,
        spaceId: UUID,
        index: Int
    ) -> SplitGroupMember {
        SplitGroupMember(
            tabId: pin.id,
            pinId: pin.id,
            origin: .spacePinned(
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
        runtimeLease: (() -> SplitShortcutRuntimeLease?)? = nil
    ) -> SplitShortcutMemberRestoreService {
        let runtimeLease = runtimeLease ?? makeRuntimeLease(fixture)
        return SplitShortcutMemberRestoreService(
            runtimeLease: runtimeLease,
            focus: makeFocusService(fixture, runtimeLease: runtimeLease),
            launcherPlacement: makeLauncherPlacementService(fixture),
            selectTabWithoutPersistence: applySelection,
            showEmptyStateWithoutPersistence: showEmptyState,
            performImmediateVisualHandoff: { _ in
                fixture.probe.visualTeardownOrder.append("handoff")
            },
            persistWindowSession: { _ in fixture.probe.sessionWrites += 1 }
        )
    }

    func makeLauncherPlacementService(
        _ fixture: SplitServiceFixture
    ) -> ShortcutSplitLauncherPlacementService {
        ShortcutSplitLauncherPlacementService(
            shortcutPin: {
                fixture.tabManager.shortcutPinCollectionStateOwner
                    .shortcutPin(by: $0)
            },
            folderSpaceId: {
                fixture.tabManager.folderCollectionStateOwner.spaceId(for: $0)
            },
            topLevelItemCount: {
                fixture.tabManager.spacePinnedStructureOwner
                    .topLevelSpacePinnedItems(for: $0).count
            },
            moveShortcut: { pin, destination in
                _ = fixture.tabManager.shortcutPinCommandOwner.moveShortcutPin(
                    pin,
                    to: destination.role,
                    profileId: destination.profileId,
                    spaceId: destination.spaceId,
                    folderId: destination.folderId,
                    index: destination.index,
                    openTargetFolder: destination.folderId != nil
                )
            }
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
        weak let splitManager = fixture.browserManager.splitManager
        return {
            guard let tabManager, let splitManager else { return nil }
            return SplitShortcutRuntimeLease(
                tabManager: tabManager,
                splitManager: splitManager
            )
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
    let firstPin: ShortcutPin
    let secondPin: ShortcutPin
    let windowState: BrowserWindowState
    let group: SplitGroup
    let probe: SplitServiceProbe

    var tabManager: TabManager { browserManager.tabManager }
}

private final class SplitServiceProbe {
    var structuralEvents = 0
    var eventsSeenAtUnload: [Int] = []
    var sessionWrites = 0
    var visualTeardownOrder: [String] = []
}
