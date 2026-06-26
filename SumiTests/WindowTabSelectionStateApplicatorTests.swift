import XCTest

@testable import Sumi

@MainActor
final class WindowTabSelectionStateApplicatorTests: XCTestCase {
    func testRegularTabSelectionUpdatesWindowSelectionMemoryAndHistory() {
        let previousTabId = UUID()
        let previousSpaceId = UUID()
        let targetSpaceId = UUID()
        let previousPinId = UUID()
        let tab = makeTab(spaceId: targetSpaceId)
        let windowState = BrowserWindowState()
        windowState.currentTabId = previousTabId
        windowState.currentSpaceId = previousSpaceId
        windowState.currentShortcutPinId = previousPinId
        windowState.currentShortcutPinRole = .spacePinned
        windowState.isShowingEmptyState = true
        windowState.selectedShortcutPinForSpace[targetSpaceId] = previousPinId

        let result = WindowTabSelectionStateApplicator.apply(
            tab,
            to: windowState,
            updateSpaceFromTab: true,
            rememberSelection: true
        )

        XCTAssertEqual(result.previousTabId, previousTabId)
        XCTAssertEqual(result.previousSpaceId, previousSpaceId)
        XCTAssertTrue(result.stateDidChange)
        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertEqual(windowState.currentSpaceId, targetSpaceId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertFalse(windowState.isShowingEmptyState)
        XCTAssertNil(windowState.selectedShortcutPinForSpace[targetSpaceId])
        XCTAssertEqual(windowState.activeTabForSpace[targetSpaceId], tab.id)
        XCTAssertEqual(windowState.recentRegularTabIdsBySpace[targetSpaceId], [tab.id])
        XCTAssertEqual(windowState.recentSelectionItemsBySpace[targetSpaceId], [.regularTab(tab.id)])
    }

    func testSpacePinnedShortcutSelectionUpdatesShortcutSelectionMemory() {
        let spaceId = UUID()
        let pin = makeShortcutPin(role: .spacePinned, spaceId: spaceId)
        let tab = makeShortcutTab(pin: pin, spaceId: spaceId)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = spaceId

        let result = WindowTabSelectionStateApplicator.apply(
            tab,
            to: windowState,
            updateSpaceFromTab: true,
            rememberSelection: true
        )

        XCTAssertNil(result.previousTabId)
        XCTAssertEqual(result.previousSpaceId, spaceId)
        XCTAssertTrue(result.stateDidChange)
        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .spacePinned)
        XCTAssertEqual(windowState.selectedShortcutPinForSpace[spaceId], pin.id)
        XCTAssertNil(windowState.activeTabForSpace[spaceId])
        XCTAssertNil(windowState.recentRegularTabIdsBySpace[spaceId])
        XCTAssertEqual(windowState.recentSelectionItemsBySpace[spaceId], [.shortcutPin(pin.id)])
    }

    func testEssentialShortcutSelectionDoesNotMoveWindowSpaceOrRememberShortcutForSpace() {
        let currentSpaceId = UUID()
        let tabSpaceId = UUID()
        let pin = makeShortcutPin(role: .essential, spaceId: nil)
        let tab = makeShortcutTab(pin: pin, spaceId: tabSpaceId)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = currentSpaceId

        let result = WindowTabSelectionStateApplicator.apply(
            tab,
            to: windowState,
            updateSpaceFromTab: true,
            rememberSelection: true
        )

        XCTAssertEqual(result.previousSpaceId, currentSpaceId)
        XCTAssertTrue(result.stateDidChange)
        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertEqual(windowState.currentSpaceId, currentSpaceId)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .essential)
        XCTAssertNil(windowState.selectedShortcutPinForSpace[currentSpaceId])
        XCTAssertNil(windowState.selectedShortcutPinForSpace[tabSpaceId])
        XCTAssertEqual(windowState.recentSelectionItemsBySpace[currentSpaceId], [.shortcutPin(pin.id)])
    }

    func testApplyingAlreadyCurrentRegularSelectionReportsNoStateChange() {
        let spaceId = UUID()
        let tab = makeTab(spaceId: spaceId)
        let windowState = BrowserWindowState()
        windowState.currentTabId = tab.id
        windowState.currentSpaceId = spaceId
        windowState.isShowingEmptyState = false
        windowState.activeTabForSpace[spaceId] = tab.id
        windowState.recentRegularTabIdsBySpace[spaceId] = [tab.id]
        windowState.recentSelectionItemsBySpace[spaceId] = [.regularTab(tab.id)]

        let result = WindowTabSelectionStateApplicator.apply(
            tab,
            to: windowState,
            updateSpaceFromTab: true,
            rememberSelection: true
        )

        XCTAssertEqual(result.previousTabId, tab.id)
        XCTAssertEqual(result.previousSpaceId, spaceId)
        XCTAssertFalse(result.stateDidChange)
        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertEqual(windowState.currentSpaceId, spaceId)
        XCTAssertEqual(windowState.activeTabForSpace[spaceId], tab.id)
        XCTAssertEqual(windowState.recentRegularTabIdsBySpace[spaceId], [tab.id])
        XCTAssertEqual(windowState.recentSelectionItemsBySpace[spaceId], [.regularTab(tab.id)])
    }

    private func makeTab(spaceId: UUID) -> Tab {
        Tab(
            url: URL(string: "https://example.com")!,
            name: "Example",
            spaceId: spaceId,
            loadsCachedFaviconOnInit: false
        )
    }

    private func makeShortcutTab(pin: ShortcutPin, spaceId: UUID?) -> Tab {
        let tab = Tab(
            url: pin.launchURL,
            name: pin.title,
            spaceId: spaceId,
            loadsCachedFaviconOnInit: false
        )
        tab.bindToShortcutPin(pin)
        return tab
    }

    private func makeShortcutPin(
        role: ShortcutPinRole,
        spaceId: UUID?
    ) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: role,
            spaceId: spaceId,
            index: 0,
            launchURL: URL(string: "https://example.com/pinned")!,
            title: "Pinned"
        )
    }
}
