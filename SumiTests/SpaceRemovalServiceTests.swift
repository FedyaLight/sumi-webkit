import Combine
import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SpaceRemovalServiceTests: XCTestCase {
    func testCannotRemoveTheLastSpace() throws {
        let tabManager = BrowserManager()
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
        let tabManager = BrowserManager()
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
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            removedSpace.id: [regularTab],
        ])
        tabManager.folderCollectionStateOwner.replaceFoldersBySpace([
            removedSpace.id: [
                TabFolder(name: "Folder", spaceId: removedSpace.id),
            ],
        ])
        tabManager.shortcutPinCollectionStateOwner
            .replaceSpacePinnedShortcuts([removedSpace.id: [pin]])
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            transientTab,
            for: pin.id,
            in: windowId,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: windowId,
                spaceID: removedSpace.id,
                profileID: removedSpace.profileId
            )
        ))
        tabManager.tabStateStore.selection.replaceCurrentTab(transientTab)
        var validationCount = 0
        var announcementCount = 0
        let observation = tabManager.objectWillChange.sink {
            announcementCount += 1
        }
        let service = makeService(
            tabManager,
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
        withExtendedLifetime(observation) {}
    }

    func testRemovalRetiresEveryLiveTabSurfaceAndPurgesWindowReferences() async throws {
        let tabManager = BrowserManager()
        let fixture = try makeLiveRemovalFixture(in: tabManager)
        let runtimeProbe = SpaceRemovalRuntimeProbe(
            windowState: fixture.windowState,
            removedSpaceId: fixture.removedSpace.id
        )
        runtimeProbe.installCleanupRuntimes(on: fixture.removedTabs)
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
        XCTAssertTrue(tabManager.splitGroupStore.groups.isEmpty)
        XCTAssertTrue(
            tabManager.tabStateStore.transientTabs
                .transientExtensionTabsByID.isEmpty
        )
        XCTAssertTrue(
            tabManager.tabStateStore.transientTabs
                .auxiliaryMiniWindowTabsByID.isEmpty
        )
        XCTAssertTrue(
            tabManager.tabStateStore.transientTabs
                .liveShortcutEntries(
                    presentedInSpace: fixture.removedSpace.id
                ).isEmpty
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

    func testBlockedPhysicalCleanupLeavesSpaceAndMembershipIntact() throws {
        let tabManager = BrowserManager()
        let fixture = try makeLiveRemovalFixture(in: tabManager)
        let runtimeProbe = SpaceRemovalRuntimeProbe(
            windowState: fixture.windowState,
            removedSpaceId: fixture.removedSpace.id
        )
        var blockedRuntime = TabWebViewCleanupRuntime.inactive
        blockedRuntime.removeAllWebViews = { _, _, _ in
            WebViewTabTeardownResult(
                discoveredWebViewCount: 1,
                cleanedWebViewCount: 0,
                deferredWebViewCount: 0,
                unscheduledProtectedWebViewCount: 0,
                blockedWebViewCount: 1
            )
        }
        fixture.regular.navigationRuntime.webViewCleanupRuntime = blockedRuntime
        let service = makeService(
            tabManager,
            runtimePorts: runtimeProbe.makeRuntimePorts()
        )

        service.removeSpace(fixture.removedSpace.id)

        XCTAssertTrue(
            tabManager.spaceStateOwner.spaces.contains {
                $0 === fixture.removedSpace
            }
        )
        XCTAssertIdentical(
            tabManager.tabStateStore.selection.currentTab,
            fixture.auxiliary
        )
        for tab in fixture.removedTabs {
            XCTAssertIdentical(
                tabManager.tabCollectionMembershipOwner.tab(for: tab.id),
                tab
            )
        }
        XCTAssertTrue(runtimeProbe.batchSplitClosures.isEmpty)
        XCTAssertTrue(runtimeProbe.extensionNotifications.isEmpty)
        XCTAssertTrue(runtimeProbe.unloadedTabIds.isEmpty)
        XCTAssertEqual(fixture.regular.webViewSession.allKnownWebViews.count, 1)
    }

    func testHistoryOnlyCleanupPersistsRepairedWindowSession() throws {
        let tabManager = BrowserManager()
        let survivingSpace = try createSpace(
            in: tabManager,
            name: "Surviving"
        )
        let removedSpace = try createSpace(in: tabManager, name: "Removed")
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
        XCTAssertEqual(persistedWindowIds, [windowState.id])
    }

    private func assertRemoval(
        of removedSpace: Space,
        keeps survivingSpace: Space,
        in tabManager: BrowserManager
    ) {
        XCTAssertEqual(
            tabManager.spaceStateOwner.spaces.map(\.id),
            [survivingSpace.id]
        )
        XCTAssertIdentical(
            tabManager.spaceStateOwner.currentSpace,
            survivingSpace
        )
        XCTAssertNil(tabManager.tabStateStore.selection.currentTab)
        XCTAssertEqual(
            tabManager.tabStateStore.regularTabs.tabs(in: removedSpace.id),
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
        XCTAssertTrue(
            tabManager.tabStateStore.transientTabs
                .liveShortcutEntries(presentedInSpace: removedSpace.id).isEmpty
        )
        XCTAssertTrue(
            tabManager.structuralPersistence.dirtySet.deletedSpaceIds
                .contains(removedSpace.id)
        )
    }

    private func makeService(
        _ tabManager: BrowserManager,
        validateWindowStates: @escaping @MainActor () -> Void
    ) -> SpaceRemovalService {
        let runtimePorts = TestRuntimePorts.make(
            validateWindowStates: {
                validateWindowStates()
                return []
            }
        )
        return makeService(tabManager, runtimePorts: runtimePorts)
    }

    private func makeService(
        _ tabManager: BrowserManager,
        runtimePorts: RuntimePortRegistry
    ) -> SpaceRemovalService {
        let runtimeConnection = TabRuntimePortConnection(runtimePorts)
        return SpaceRemovalService(
            transactions: tabManager.structuralLookupCoordinator,
            contentRetirement: SpaceContentRetirementService(
                state: tabManager.tabStateStore,
                structuralMutations: tabManager.structuralCollectionMutationOwner,
                splitGroups: SpaceSplitGroupRetirementService(
                    store: tabManager.splitGroupStore,
                    mutations: tabManager.splitGroupMutations
                ),
                liveShortcutRetirement: LiveShortcutTabBatchRetirement(
                    storage: tabManager.tabStateStore.transientTabs,
                    structuralLookup: tabManager.structuralLookupCoordinator
                ),
                runtimeTeardown: TabRuntimeTeardownService(
                    persistence: tabManager.structuralPersistence,
                    membership: tabManager.tabCollectionMembershipOwner,
                    webViewSessions: tabManager.tabFactory.webViewSessions
                )
            ),
            windowStates: DeletedSpaceWindowStateReconciler(
                runtimeConnection: runtimeConnection
            ),
            catalog: SpaceRemovalCatalogCommitter(
                state: tabManager.tabStateStore,
                persistence: tabManager.structuralPersistence,
                changes: tabManager.objectWillChange
            )
        )
    }

    private func makeLiveTab(
        path: String,
        spaceId: UUID,
        tabManager: BrowserManager
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
        in tabManager: BrowserManager
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
        let shortcutWindowID = UUID()
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            shortcut,
            for: pin.id,
            in: shortcutWindowID,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: shortcutWindowID,
                spaceID: removedSpace.id,
                profileID: removedSpace.profileId
            )
        ))
        membership.registerTransientExtensionTab(transientExtension)
        membership.registerAuxiliaryMiniWindowTab(auxiliary)
        tabManager.tabStateStore.selection.replaceCurrentTab(auxiliary)
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
        tabManager: BrowserManager
    ) throws -> (SplitGroup, SplitGroup) {
        let shortcutPinID = try XCTUnwrap(
            deletedHostTabs.1.shortcutPinId
        )
        let deletedHostGroup = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(deletedHostTabs.0.id),
                    .shortcutPin(
                        shortcutPinID,
                        returnPlacement: .spacePinned(
                            spaceId: removedSpaceId,
                            folderId: nil,
                            index: 0
                        )
                    ),
                ],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: removedSpaceId)
            )
        )
        let crossSpaceGroup = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(crossSpaceTabs.0.id),
                    .regularTab(crossSpaceTabs.1.id),
                ],
                layoutKind: .horizontal,
                container: .regularTabs(spaceId: survivingSpaceId)
            )
        )
        tabManager.splitGroupStore.replaceAll(
            with: [deletedHostGroup, crossSpaceGroup]
        )
        return (deletedHostGroup, crossSpaceGroup)
    }

    private func createSpace(
        in browser: BrowserManager,
        name: String
    ) throws -> Space {
        try XCTUnwrap(browser.sidebarSpaceLifecycle.createSpace(
            name: name,
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: nil
        ))
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
        presentationState.pendingSplitGroupFocusRequest = SplitGroupFocusRequest(
            groupID: pendingGroupId,
            preferredMemberID: nil,
            targetSpaceID: pendingGroupSpaceId
        )
        restorationState.pendingSplitSelection = PendingWindowSplitSelection(
            groupID: sessionGroupId,
            preferredMemberID: nil
        )
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
                retirement: .rejecting,
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

    func installCleanupRuntimes(on tabs: [Tab]) {
        for tab in tabs {
            var runtime = TabWebViewCleanupRuntime.inactive
            runtime.removeAllWebViews = { [weak self] tab, closeFullscreen, intent in
                XCTAssertEqual(intent, .retirement)
                self?.fullscreenCloseRequests.append(closeFullscreen)
                self?.removedWebViewTabIds.insert(tab.id)
                return WebViewTabTeardownResult(
                    discoveredWebViewCount: 1,
                    cleanedWebViewCount: 1,
                    deferredWebViewCount: 0,
                    unscheduledProtectedWebViewCount: 0
                )
            }
            tab.navigationRuntime.webViewCleanupRuntime = runtime
        }
    }

    private func isClean(_ persisted: BrowserWindowState) -> Bool {
        persisted.activeTabForSpace[removedSpaceId] == nil
            && persisted.selectedShortcutPinForSpace[removedSpaceId] == nil
            && persisted.selectionHistory
                .recentRegularTabIdsBySpace[removedSpaceId] == nil
            && persisted.selectionHistory
                .recentSelectionItemsBySpace[removedSpaceId] == nil
            && persisted.presentationState.pendingSplitGroupFocusRequest == nil
            && persisted.restorationState.pendingSplitSelection == nil
    }
}
