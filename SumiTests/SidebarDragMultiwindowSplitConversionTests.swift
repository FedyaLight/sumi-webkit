import Combine
import Foundation
import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class SidebarDragMultiwindowSplitConversionTests: XCTestCase {
    func testSplitVisibleRegularTabDropConvertsMultiwindowSplitAtomically() throws {
        try assertConversionCommitted(secondarySelectsDraggedTab: false)
    }

    func testSelectedSplitVisibleRegularTabDropConvertsMultiwindowSplitAtomically() throws {
        try assertConversionCommitted(secondarySelectsDraggedTab: true)
    }

    private func assertConversionCommitted(
        secondarySelectsDraggedTab: Bool
    ) throws {
        let primaryWindow = BrowserWindowState()
        let secondaryWindow = BrowserWindowState()
        let uninvolvedWindow = BrowserWindowState()
        let states = [
            primaryWindow.id: primaryWindow,
            secondaryWindow.id: secondaryWindow,
            uninvolvedWindow.id: uninvolvedWindow,
        ]
        var visibleSplitIdsByWindow: [UUID: [UUID]] = [:]
        var primaryTrackedTabId: UUID?
        var persistedWindowIds: [UUID] = []
        let tabManager = BrowserManager()
        tabManager.runtimePortConnection.attach(TestRuntimePorts.make(
            windowState: { states[$0] },
            windows: { states.map { ($0.key, $0.value) } },
            webViewLifecycle: TestRuntimePorts.webViewLifecycle(
                retirement: .rejecting,
                primaryTrackedWindowId: { tabId in
                    tabId == primaryTrackedTabId ? primaryWindow.id : nil
                }
            ),
            visibleSplitTabIds: { visibleSplitIdsByWindow[$0] ?? [] },
            persistWindowSession: { persistedWindowIds.append($0.id) }
        ))
        states.values.forEach { tabManager.windowRegistry.register($0) }
        let profileId = UUID()
        let space = try XCTUnwrap(tabManager.sidebarSpaceLifecycle.createSpace(
            name: "Work",
            icon: SumiPersistentGlyph.spaceDefaultIconValue,
            profileID: profileId
        ))
        let companion = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/current",
            in: space
        )
        let draggedTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/multiwindow-split",
            in: space,
            activate: false
        )
        primaryTrackedTabId = draggedTab.id
        for window in states.values {
            window.currentSpaceId = space.id
            window.currentProfileId = profileId
        }
        for window in [primaryWindow, secondaryWindow] {
            window.activeTabForSpace[space.id] = draggedTab.id
            window.selectionHistory.recordRegularTabSelection(
                draggedTab.id,
                in: space.id
            )
        }
        primaryWindow.currentTabId = draggedTab.id
        secondaryWindow.currentTabId = secondarySelectsDraggedTab
            ? draggedTab.id
            : companion.id
        uninvolvedWindow.currentTabId = companion.id
        uninvolvedWindow.activeTabForSpace[space.id] = companion.id
        uninvolvedWindow.selectionHistory.recordRegularTabSelection(
            companion.id,
            in: space.id
        )
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [
                    .regularTab(companion.id),
                    .regularTab(draggedTab.id),
                ],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        visibleSplitIdsByWindow = [
            primaryWindow.id: [companion.id, draggedTab.id],
            secondaryWindow.id: [companion.id, draggedTab.id],
        ]
        XCTAssertTrue(
            tabManager.splitGroupMutations.insert(group, persist: false)
        )
        primaryWindow.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(draggedTab.id)
        )
        let uninvolvedSession = ShortcutConversionWindowSessionState(
            uninvolvedWindow
        )
        let uninvolvedHistory = uninvolvedWindow.selectionHistory
            .recentRegularTabIdsBySpace
        var structuralEvents = 0
        let cancellable = tabManager.tabStructureEventBus
            .structureChangedPublisher.sink { structuralEvents += 1 }
        structuralEvents = 0

        let didMove = tabManager.sidebarDragRouter
            .performSidebarDragOperation(
                DragOperation(
                    payload: .tab(draggedTab),
                    scope: try makeScope(
                        spaceId: space.id,
                        profileId: profileId,
                        sourceZone: .spaceRegular(space.id),
                        item: dragItem(draggedTab),
                        windowState: primaryWindow
                    ),
                    fromContainer: .spaceRegular(space.id),
                    toContainer: .spacePinned(space.id),
                    toIndex: 0
                )
            )

        XCTAssertTrue(didMove)
        XCTAssertEqual(structuralEvents, 1)
        XCTAssertEqual(persistedWindowIds.count, 2)
        XCTAssertEqual(
            Set(persistedWindowIds),
            [primaryWindow.id, secondaryWindow.id]
        )
        XCTAssertFalse(tabManager.regularTabCollectionOwner.contains(draggedTab))
        XCTAssertTrue(draggedTab.isShortcutLiveInstance)

        let pins = tabManager.shortcutPinCollectionStateOwner
            .spacePinnedPins(for: space.id)
        let pin = try XCTUnwrap(pins.first)
        XCTAssertEqual(pins.count, 1)
        let replacementMember = SplitMember.shortcutPin(
            pin.id,
            returnPlacement: .spacePinned(
                spaceId: space.id,
                folderId: nil,
                index: 0
            )
        )
        XCTAssertEqual(
            tabManager.splitGroupStore.group(id: group.id),
            group.replacingMember(
                .regularTab(draggedTab.id),
                with: replacementMember
            )
        )

        let primaryLiveTab = try XCTUnwrap(
            tabManager.liveShortcutTabs.tab(
                for: pin.id,
                in: primaryWindow.id
            )
        )
        let secondaryLiveTab = try XCTUnwrap(
            tabManager.liveShortcutTabs.tab(
                for: pin.id,
                in: secondaryWindow.id
            )
        )
        XCTAssertIdentical(primaryLiveTab, draggedTab)
        XCTAssertNotIdentical(secondaryLiveTab, draggedTab)
        XCTAssertNil(
            tabManager.liveShortcutTabs.tab(
                for: pin.id,
                in: uninvolvedWindow.id
            )
        )
        XCTAssertEqual(
            tabManager.liveShortcutTabs.entries(for: pin.id).count,
            2
        )

        XCTAssertEqual(primaryWindow.currentTabId, primaryLiveTab.id)
        XCTAssertEqual(primaryWindow.currentShortcutPinId, pin.id)
        XCTAssertEqual(
            primaryWindow.splitSelection,
            WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .shortcutPin(pin.id)
            )
        )
        XCTAssertEqual(
            secondaryWindow.currentTabId,
            secondarySelectsDraggedTab ? secondaryLiveTab.id : companion.id
        )
        XCTAssertEqual(
            secondaryWindow.currentShortcutPinId,
            secondarySelectsDraggedTab ? pin.id : nil
        )
        XCTAssertNil(secondaryWindow.splitSelection)

        for window in [primaryWindow, secondaryWindow] {
            XCTAssertEqual(window.activeTabForSpace[space.id], companion.id)
            XCTAssertFalse(
                window.selectionHistory.recentRegularTabIdsBySpace[space.id]?
                    .contains(draggedTab.id) == true
            )
        }
        XCTAssertEqual(
            ShortcutConversionWindowSessionState(uninvolvedWindow),
            uninvolvedSession
        )
        XCTAssertEqual(
            uninvolvedWindow.selectionHistory.recentRegularTabIdsBySpace,
            uninvolvedHistory
        )
        _ = cancellable
    }

    private func makeScope(
        spaceId: UUID,
        profileId: UUID,
        sourceZone: DropZoneID,
        item: SumiDragItem,
        windowState: BrowserWindowState
    ) throws -> SidebarDragScope {
        windowState.currentSpaceId = spaceId
        windowState.currentProfileId = profileId
        return try XCTUnwrap(
            SidebarDragScope(
                windowState: windowState,
                sourceZone: sourceZone,
                item: item
            )
        )
    }

    private func dragItem(_ tab: Tab) -> SumiDragItem {
        SumiDragItem(
            tabId: tab.id,
            title: tab.name,
            urlString: tab.url.absoluteString
        )
    }
}
