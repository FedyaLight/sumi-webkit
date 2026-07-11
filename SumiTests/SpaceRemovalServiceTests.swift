import Foundation
@testable import Sumi
import WebKit
import XCTest

@MainActor
final class SpaceRemovalServiceTests: XCTestCase {
    func testCannotRemoveTheLastSpace() throws {
        let tabManager = try makeInMemoryTabManager()
        let onlySpace = Space(name: "Only")
        tabManager.spaceStateOwner.replaceSpaces([onlySpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(onlySpace)
        var validationCount = 0
        let service = makeService(tabManager) { validationCount += 1 }

        service.removeSpace(onlySpace.id)

        XCTAssertEqual(tabManager.spaceStateOwner.spaces.map(\.id), [onlySpace.id])
        XCTAssertEqual(validationCount, 0)
    }

    func testRemovalClearsEverySpaceScopedCollectionAndRepairsSelection() throws {
        let tabManager = try makeInMemoryTabManager()
        let survivingSpace = Space(name: "Surviving")
        let removedSpace = Space(name: "Removed")
        tabManager.spaceStateOwner.replaceSpaces([
            survivingSpace,
            removedSpace,
        ])
        tabManager.spaceStateOwner.replaceCurrentSpace(removedSpace)

        let regularURL = try XCTUnwrap(URL(string: "https://regular.example"))
        let shortcutURL = try XCTUnwrap(URL(string: "https://shortcut.example"))
        let regularTab = Tab(
            url: regularURL,
            spaceId: removedSpace.id,
            loadsCachedFaviconOnInit: false
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: removedSpace.id,
            index: 0,
            launchURL: shortcutURL,
            title: "Shortcut"
        )
        let transientTab = Tab(
            url: pin.launchURL,
            spaceId: removedSpace.id,
            loadsCachedFaviconOnInit: false
        )
        transientTab.bindToShortcutPin(pin)
        let windowId = UUID()
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            removedSpace.id: [regularTab],
        ])
        tabManager.folderCollectionStateOwner.replaceFoldersBySpace([
            removedSpace.id: [
                TabFolder(name: "Folder", spaceId: removedSpace.id),
            ],
        ])
        tabManager.shortcutPinCollectionStateOwner
            .replaceSpacePinnedShortcuts([removedSpace.id: [pin]])
        tabManager.transientTabRegistryOwner
            .replaceTransientShortcutTabsByWindow([
                windowId: [pin.id: transientTab],
            ])
        tabManager.selectionStateOwner.replaceCurrentTab(transientTab)
        var validationCount = 0
        var announcementCount = 0
        let service = makeService(
            tabManager,
            announceChange: { announcementCount += 1 },
            validateWindowStates: { validationCount += 1 }
        )

        service.removeSpace(removedSpace.id)

        assertRemoval(
            of: removedSpace,
            keeps: survivingSpace,
            in: tabManager
        )
        XCTAssertEqual(announcementCount, 1)
        XCTAssertEqual(validationCount, 1)
    }

    func testRemovalRetiresEveryLiveTabSurfaceAndPurgesWindowReferences() async throws {
        let tabManager = try makeInMemoryTabManager()
        let fixture = try makeLiveRemovalFixture(in: tabManager)
        let runtimeProbe = SpaceRemovalRuntimeProbe(
            windowState: fixture.windowState,
            removedSpaceId: fixture.removedSpace.id
        )
        let service = makeService(
            tabManager,
            runtimePorts: runtimeProbe.makeRuntimePorts()
        )
        tabManager.structuralPersistence.scheduleRuntimeStatePersistence(
            for: fixture.regular
        )

        service.removeSpace(fixture.removedSpace.id)

        XCTAssertEqual(runtimeProbe.batchSplitClosures, [fixture.removedTabIds])
        XCTAssertEqual(runtimeProbe.individualSplitClosureCount, 0)
        XCTAssertEqual(runtimeProbe.extensionNotifications, fixture.removedTabIds)
        XCTAssertEqual(runtimeProbe.unloadedTabIds, fixture.removedTabIds)
        XCTAssertEqual(runtimeProbe.removedWebViewTabIds, fixture.removedTabIds)
        XCTAssertEqual(runtimeProbe.fullscreenCloseRequests, [true, true, true, true])
        XCTAssertEqual(runtimeProbe.auxiliaryCloseTabIds, [fixture.auxiliary.id])
        XCTAssertTrue(tabManager.splitGroupCollectionStateOwner.splitGroups.isEmpty)
        XCTAssertTrue(
            tabManager.transientTabRegistryOwner
                .transientExtensionTabsByID.isEmpty
        )
        XCTAssertTrue(
            tabManager.transientTabRegistryOwner
                .auxiliaryMiniWindowTabsByID.isEmpty
        )
        XCTAssertTrue(
            tabManager.transientTabRegistryOwner
                .transientShortcutTabs(inSpace: fixture.removedSpace.id).isEmpty
        )
        let membership = tabManager.tabCollectionMembershipOwner
        for tab in fixture.removedTabs {
            XCTAssertTrue(tab.webViewSession.allKnownWebViews.isEmpty)
            XCTAssertNil(membership.tab(for: tab.id))
        }
        XCTAssertIdentical(
            membership.tab(for: fixture.survivingTab.id),
            fixture.survivingTab
        )
        XCTAssertNil(fixture.windowState.currentSpaceId)
        XCTAssertNil(fixture.windowState.currentTabId)
        XCTAssertNil(fixture.windowState.currentShortcutPinId)
        XCTAssertEqual(runtimeProbe.validationCount, 1)
        XCTAssertEqual(runtimeProbe.persistedStateWasClean, [true])
        let flushedRuntimeStates = await tabManager.structuralPersistence
            .flushRuntimeStatePersistenceAwaitingResult()
        XCTAssertEqual(flushedRuntimeStates, 0)
    }

    func testHistoryOnlyCleanupDoesNotPersistWindowSession() throws {
        let tabManager = try makeInMemoryTabManager()
        let survivingSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Surviving"
        )
        let removedSpace = tabManager.spaceServices.catalog.createSpace(
            name: "Removed"
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = survivingSpace.id
        windowState.currentTabId = UUID()
        windowState.selectionHistory
            .recentRegularTabIdsBySpace[removedSpace.id] = [UUID()]
        var persistedWindowIds: [UUID] = []
        let runtime = TestRuntimePorts.make(
            windowState: { $0 == windowState.id ? windowState : nil },
            windows: { [(windowState.id, windowState)] },
            windowStates: { [windowState] },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )

        makeService(tabManager, runtimePorts: runtime)
            .removeSpace(removedSpace.id)

        XCTAssertNil(
            windowState.selectionHistory
                .recentRegularTabIdsBySpace[removedSpace.id]
        )
        XCTAssertTrue(persistedWindowIds.isEmpty)
    }

    private func assertRemoval(
        of removedSpace: Space,
        keeps survivingSpace: Space,
        in tabManager: TabManager
    ) {
        XCTAssertEqual(
            tabManager.spaceStateOwner.spaces.map(\.id),
            [survivingSpace.id]
        )
        XCTAssertIdentical(
            tabManager.spaceStateOwner.currentSpace,
            survivingSpace
        )
        XCTAssertNil(tabManager.selectionStateOwner.currentTab)
        XCTAssertEqual(
            tabManager.regularTabCollectionStateOwner.tabs(in: removedSpace.id),
            []
        )
        XCTAssertEqual(
            tabManager.folderCollectionStateOwner.folders(for: removedSpace.id),
            []
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: removedSpace.id),
            []
        )
        XCTAssertEqual(
            tabManager.transientTabRegistryOwner
                .transientShortcutTabs(inSpace: removedSpace.id),
            []
        )
        XCTAssertTrue(
            tabManager.structuralPersistence.dirtySet.deletedSpaceIds
                .contains(removedSpace.id)
        )
    }

    private func makeService(
        _ tabManager: TabManager,
        announceChange: @escaping @MainActor () -> Void = { /* No-op. */ },
        validateWindowStates: @escaping @MainActor () -> Void
    ) -> SpaceRemovalService {
        let runtimePorts = TestRuntimePorts.make(
            validateWindowStates: {
                validateWindowStates()
                return []
            }
        )
        return makeService(tabManager, runtimePorts: runtimePorts, announceChange: announceChange)
    }

    private func makeService(
        _ tabManager: TabManager,
        runtimePorts: RuntimePortRegistry,
        announceChange: @escaping @MainActor () -> Void = { /* No-op. */ }
    ) -> SpaceRemovalService {
        SpaceRemovalService(
            state: tabManager.stateStore,
            persistence: tabManager.structuralPersistence,
            transactions: tabManager.structuralLookupCoordinator,
            contentRetirement: SpaceContentRetirementService(
                state: tabManager.stateStore,
                structuralMutations: tabManager.structuralCollectionMutationOwner,
                splitGroups: tabManager.splitGroupStructureOwner,
                liveShortcutTabs: tabManager.liveShortcutTabs,
                runtimeTeardown: TabRuntimeTeardownService(
                    persistence: tabManager.structuralPersistence,
                    membership: tabManager.tabCollectionMembershipOwner
                )
            ),
            windowStates: DeletedSpaceWindowStateReconciler(
                runtimePorts: { runtimePorts }
            ),
            announceChange: announceChange
        )
    }

    private func makeLiveTab(
        path: String,
        spaceId: UUID,
        tabManager: TabManager
    ) -> Tab {
        tabManager.tabFactory.makeTab(
            url: URL(string: "https://\(path).example")
                ?? URL(fileURLWithPath: "/"),
            spaceId: spaceId,
            existingWebView: WKWebView(),
            loadsCachedFaviconOnInit: false
        )
    }

    private func makeLiveRemovalFixture(
        in tabManager: TabManager
    ) throws -> SpaceRemovalFixture {
        let survivingSpace = Space(name: "Surviving")
        let removedSpace = Space(name: "Removed")
        tabManager.spaceStateOwner.replaceSpaces([survivingSpace, removedSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(removedSpace)
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: removedSpace.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://shortcut.example")),
            title: "Shortcut"
        )
        let regular = makeLiveTab(path: "regular", spaceId: removedSpace.id, tabManager: tabManager)
        let shortcut = makeLiveTab(path: "shortcut", spaceId: removedSpace.id, tabManager: tabManager)
        shortcut.bindToShortcutPin(pin)
        let transientExtension = makeLiveTab(path: "extension", spaceId: removedSpace.id, tabManager: tabManager)
        let auxiliary = makeLiveTab(path: "auxiliary", spaceId: removedSpace.id, tabManager: tabManager)
        auxiliary.isAuxiliaryMiniWindow = true
        let survivingTab = tabManager.tabFactory.makeTab(
            url: try XCTUnwrap(URL(string: "https://surviving.example")),
            spaceId: survivingSpace.id,
            loadsCachedFaviconOnInit: false
        )
        let membership = tabManager.tabCollectionMembershipOwner
        [regular, shortcut, transientExtension, auxiliary, survivingTab]
            .forEach(membership.attach)
        tabManager.structuralCollectionMutationOwner.setTabs([regular], for: removedSpace.id)
        tabManager.structuralCollectionMutationOwner.setTabs([survivingTab], for: survivingSpace.id)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: removedSpace.id)
        tabManager.transientTabRegistryOwner
            .replaceTransientShortcutTabsByWindow([UUID(): [pin.id: shortcut]])
        membership.registerTransientExtensionTab(transientExtension)
        membership.registerAuxiliaryMiniWindowTab(auxiliary)
        tabManager.selectionStateOwner.replaceCurrentTab(auxiliary)
        let groups = try installSplitGroups(
            removedSpaceId: removedSpace.id,
            survivingSpaceId: survivingSpace.id,
            deletedHostTabs: (regular, shortcut),
            crossSpaceTabs: (transientExtension, survivingTab),
            tabManager: tabManager
        )
        let windowState = BrowserWindowState()
        windowState.installRemovalReferences(
            space: removedSpace,
            regular: regular,
            shortcutPin: pin,
            pendingGroupId: groups.1.id,
            sessionGroupId: groups.0.id,
            pendingGroupSpaceId: survivingSpace.id
        )
        return SpaceRemovalFixture(
            removedSpace: removedSpace,
            regular: regular,
            shortcut: shortcut,
            transientExtension: transientExtension,
            auxiliary: auxiliary,
            survivingTab: survivingTab,
            windowState: windowState
        )
    }

    private func installSplitGroups(
        removedSpaceId: UUID,
        survivingSpaceId: UUID,
        deletedHostTabs: (Tab, Tab),
        crossSpaceTabs: (Tab, Tab),
        tabManager: TabManager
    ) throws -> (SplitGroup, SplitGroup) {
        let deletedHostGroup = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [deletedHostTabs.0.id, deletedHostTabs.1.id],
                layoutKind: .vertical,
                host: .shortcutPinned(
                    spaceId: removedSpaceId,
                    profileId: nil,
                    index: 0
                )
            )
        )
        let crossSpaceGroup = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [crossSpaceTabs.0.id, crossSpaceTabs.1.id],
                layoutKind: .horizontal,
                host: .regular(spaceId: survivingSpaceId)
            )
        )
        tabManager.splitGroupCollectionStateOwner.replaceSplitGroups([
            deletedHostGroup,
            crossSpaceGroup,
        ])
        return (deletedHostGroup, crossSpaceGroup)
    }
}

@MainActor
private struct SpaceRemovalFixture {
    let removedSpace: Space
    let regular: Tab
    let shortcut: Tab
    let transientExtension: Tab
    let auxiliary: Tab
    let survivingTab: Tab
    let windowState: BrowserWindowState

    var removedTabs: [Tab] {
        [regular, shortcut, transientExtension, auxiliary]
    }

    var removedTabIds: Set<UUID> { Set(removedTabs.map(\.id)) }
}

private extension BrowserWindowState {
    func installRemovalReferences(
        space: Space,
        regular: Tab,
        shortcutPin: ShortcutPin,
        pendingGroupId: UUID,
        sessionGroupId: UUID,
        pendingGroupSpaceId: UUID
    ) {
        currentSpaceId = space.id
        currentTabId = regular.id
        currentShortcutPinId = shortcutPin.id
        currentShortcutPinRole = .spacePinned
        activeTabForSpace[space.id] = regular.id
        selectedShortcutPinForSpace[space.id] = shortcutPin.id
        selectionHistory.recentRegularTabIdsBySpace[space.id] = [regular.id]
        selectionHistory.recentSelectionItemsBySpace[space.id] = [
            .regularTab(regular.id),
            .shortcutPin(shortcutPin.id),
        ]
        pendingSplitGroupFocusRequest = SplitGroupFocusRequest(
            groupId: pendingGroupId,
            targetSpaceId: pendingGroupSpaceId
        )
        pendingSessionSplitGroupId = sessionGroupId
    }
}

@MainActor
private final class SpaceRemovalRuntimeProbe {
    private let windowState: BrowserWindowState
    private let removedSpaceId: UUID

    var batchSplitClosures: [Set<UUID>] = []
    var individualSplitClosureCount = 0
    var extensionNotifications = Set<UUID>()
    var unloadedTabIds = Set<UUID>()
    var removedWebViewTabIds = Set<UUID>()
    var fullscreenCloseRequests: [Bool] = []
    var auxiliaryCloseTabIds = Set<UUID>()
    var validationCount = 0
    var persistedStateWasClean: [Bool] = []

    init(windowState: BrowserWindowState, removedSpaceId: UUID) {
        self.windowState = windowState
        self.removedSpaceId = removedSpaceId
    }

    func makeRuntimePorts() -> RuntimePortRegistry {
        TestRuntimePorts.make(
            windowStates: { [windowState] in [windowState] },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                unloadTab: { [weak self] in self?.unloadedTabIds.insert($0.id) },
                requireRemoveAllWebViews: { [weak self] tab, closeFullscreen in
                    self?.fullscreenCloseRequests.append(closeFullscreen)
                    self?.removedWebViewTabIds.insert(tab.id)
                }
            ),
            handleTabClosure: { [weak self] _ in
                self?.individualSplitClosureCount += 1
            },
            handleTabClosures: { [weak self] in
                self?.batchSplitClosures.append($0)
            },
            notifyTabClosedIfLoaded: { [weak self] in
                self?.extensionNotifications.insert($0.id)
            },
            validateWindowStates: { [weak self] in
                self?.validationCount += 1
                return []
            },
            persistWindowSession: { [weak self] in
                guard let self else { return }
                persistedStateWasClean.append(isClean($0))
            },
            closeAuxiliaryMiniWindow: { [weak self] tab, _ in
                self?.auxiliaryCloseTabIds.insert(tab.id)
            }
        )
    }

    private func isClean(_ persisted: BrowserWindowState) -> Bool {
        persisted.activeTabForSpace[removedSpaceId] == nil
            && persisted.selectedShortcutPinForSpace[removedSpaceId] == nil
            && persisted.selectionHistory
                .recentRegularTabIdsBySpace[removedSpaceId] == nil
            && persisted.selectionHistory
                .recentSelectionItemsBySpace[removedSpaceId] == nil
            && persisted.pendingSplitGroupFocusRequest == nil
            && persisted.pendingSessionSplitGroupId == nil
    }
}
