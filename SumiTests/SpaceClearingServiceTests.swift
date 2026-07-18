import Combine
import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class SpaceClearingServiceTests: XCTestCase {
    func testClearRetiresSpaceScopedCollectionsButKeepsSpace() throws {
        let tabManager = BrowserManager()
        let otherSpace = Space(name: "Other")
        let clearedSpace = Space(name: "Cleared")
        tabManager.spaceStateOwner.replaceSpaces([otherSpace, clearedSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(clearedSpace)

        let regularURL = try XCTUnwrap(URL(string: "https://regular.example"))
        let shortcutURL = try XCTUnwrap(URL(string: "https://shortcut.example"))
        let regularTab = Tab(
            url: regularURL,
            spaceId: clearedSpace.id,
            loadsCachedFaviconOnInit: false
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: clearedSpace.id,
            index: 0,
            launchURL: shortcutURL,
            title: "Shortcut"
        )
        let transientTab = Tab(
            url: pin.launchURL,
            spaceId: clearedSpace.id,
            loadsCachedFaviconOnInit: false
        )
        transientTab.bindToShortcutPin(pin)
        let windowId = UUID()
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            clearedSpace.id: [regularTab],
        ])
        tabManager.folderCollectionStateOwner.replaceFoldersBySpace([
            clearedSpace.id: [
                TabFolder(name: "Folder", spaceId: clearedSpace.id),
            ],
        ])
        tabManager.shortcutPinCollectionStateOwner
            .replaceSpacePinnedShortcuts([clearedSpace.id: [pin]])
        XCTAssertTrue(tabManager.liveShortcutTabs.register(
            transientTab,
            for: pin.id,
            in: windowId,
            presentationPage: LiveShortcutPresentationPageReceipt(
                windowID: windowId,
                spaceID: clearedSpace.id,
                profileID: clearedSpace.profileId
            )
        ))
        tabManager.tabStateStore.selection.replaceCurrentTab(transientTab)
        var validationCount = 0
        let service = makeService(
            tabManager,
            runtimePorts: TestRuntimePorts.make(
                validateWindowStates: {
                    validationCount += 1
                    return []
                }
            )
        )

        service.clearSpace(clearedSpace.id)

        XCTAssertEqual(
            tabManager.spaceStateOwner.spaces.map(\.id),
            [otherSpace.id, clearedSpace.id]
        )
        XCTAssertIdentical(
            tabManager.spaceStateOwner.currentSpace,
            clearedSpace
        )
        XCTAssertNil(tabManager.tabStateStore.selection.currentTab)
        XCTAssertEqual(
            tabManager.tabStateStore.regularTabs.tabs(in: clearedSpace.id),
            []
        )
        XCTAssertEqual(
            tabManager.folderCollectionStateOwner.folders(for: clearedSpace.id),
            []
        )
        XCTAssertEqual(
            tabManager.shortcutPinCollectionStateOwner
                .spacePinnedPins(for: clearedSpace.id),
            []
        )
        XCTAssertTrue(
            tabManager.tabStateStore.transientTabs
                .liveShortcutEntries(presentedInSpace: clearedSpace.id).isEmpty
        )
        XCTAssertFalse(
            tabManager.structuralPersistence.dirtySet.deletedSpaceIds
                .contains(clearedSpace.id)
        )
        XCTAssertEqual(validationCount, 1)
    }

    func testClearWorksForTheLastSpace() throws {
        let tabManager = BrowserManager()
        let onlySpace = Space(name: "Only")
        tabManager.spaceStateOwner.replaceSpaces([onlySpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(onlySpace)
        let regularTab = Tab(
            url: try XCTUnwrap(URL(string: "https://regular.example")),
            spaceId: onlySpace.id,
            loadsCachedFaviconOnInit: false
        )
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            onlySpace.id: [regularTab],
        ])
        let service = makeService(tabManager, runtimePorts: TestRuntimePorts.make())

        service.clearSpace(onlySpace.id)

        XCTAssertEqual(
            tabManager.spaceStateOwner.spaces.map(\.id),
            [onlySpace.id]
        )
        XCTAssertIdentical(
            tabManager.spaceStateOwner.currentSpace,
            onlySpace
        )
        XCTAssertEqual(
            tabManager.tabStateStore.regularTabs.tabs(in: onlySpace.id),
            []
        )
        XCTAssertFalse(
            tabManager.structuralPersistence.dirtySet.deletedSpaceIds
                .contains(onlySpace.id)
        )
    }

    func testClearKeepsWindowCurrentSpaceWhilePruningRetiredReferences() throws {
        let tabManager = BrowserManager()
        let clearedSpace = Space(name: "Cleared")
        tabManager.spaceStateOwner.replaceSpaces([clearedSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(clearedSpace)
        let regularTab = Tab(
            url: try XCTUnwrap(URL(string: "https://regular.example")),
            spaceId: clearedSpace.id,
            loadsCachedFaviconOnInit: false
        )
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            clearedSpace.id: [regularTab],
        ])
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = clearedSpace.id
        windowState.currentTabId = regularTab.id
        windowState.activeTabForSpace[clearedSpace.id] = regularTab.id
        windowState.selectionHistory
            .recentRegularTabIdsBySpace[clearedSpace.id] = [regularTab.id]
        var persistedWindowIds: [UUID] = []
        let runtime = TestRuntimePorts.make(
            windowState: { $0 == windowState.id ? windowState : nil },
            windows: { [(windowState.id, windowState)] },
            windowStates: { [windowState] },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        )

        makeService(tabManager, runtimePorts: runtime)
            .clearSpace(clearedSpace.id)

        XCTAssertEqual(windowState.currentSpaceId, clearedSpace.id)
        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.activeTabForSpace[clearedSpace.id])
        XCTAssertNil(
            windowState.selectionHistory
                .recentRegularTabIdsBySpace[clearedSpace.id]
        )
        XCTAssertEqual(persistedWindowIds, [windowState.id])
    }

    func testBlockedPhysicalCleanupLeavesContentIntact() throws {
        let tabManager = BrowserManager()
        let clearedSpace = Space(name: "Cleared")
        tabManager.spaceStateOwner.replaceSpaces([clearedSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(clearedSpace)
        let regular = tabManager.tabFactory.makeTab(
            url: try XCTUnwrap(URL(string: "https://regular.example")),
            spaceId: clearedSpace.id,
            existingWebView: WKWebView(),
            loadsCachedFaviconOnInit: false
        )
        tabManager.tabCollectionMembershipOwner.attach(regular)
        tabManager.structuralCollectionMutationOwner.setTabs(
            [regular],
            for: clearedSpace.id
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
        regular.navigationRuntime.webViewCleanupRuntime = blockedRuntime
        let service = makeService(tabManager, runtimePorts: TestRuntimePorts.make())

        service.clearSpace(clearedSpace.id)

        XCTAssertEqual(
            tabManager.tabStateStore.regularTabs.tabs(in: clearedSpace.id),
            [regular]
        )
        XCTAssertIdentical(
            tabManager.tabCollectionMembershipOwner.tab(for: regular.id),
            regular
        )
        XCTAssertEqual(regular.webViewSession.allKnownWebViews.count, 1)
    }

    private func makeService(
        _ tabManager: BrowserManager,
        runtimePorts: RuntimePortRegistry
    ) -> SpaceClearingService {
        let runtimeConnection = TabRuntimePortConnection(runtimePorts)
        return SpaceClearingService(
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
            persistence: tabManager.structuralPersistence
        )
    }
}
