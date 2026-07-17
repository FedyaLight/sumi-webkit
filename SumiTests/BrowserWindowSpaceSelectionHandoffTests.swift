import Foundation
@testable import Sumi
import XCTest

@MainActor
final class BrowserWindowSpaceSelectionHandoffTests: XCTestCase {
    func testResolvedTabIsSelectedBeforeImmediateVisualHandoff() throws {
        let tabManager = BrowserManager()
        let space = Space(name: "Target", profileId: UUID())
        let tab = makeTab(in: space)
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.tabStateStore.regularTabs.replaceTabsBySpace([
            space.id: [tab],
        ])
        let windowState = BrowserWindowState()
        tabManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        tabManager.windowRegistry.register(windowState)
        let handoff = BrowserWindowSpaceSelectionHandoff(
            tabContext: tabManager.shellRuntime.windowTabs,
            selection: tabManager.browserTabSelection,
            visuals: tabManager.shellRuntime.windowVisuals
        )

        let target = handoff.resolveTarget(for: space, in: windowState)
        handoff.present(target, in: windowState)

        XCTAssertIdentical(target.preferredTab, tab)
        XCTAssertEqual(windowState.currentTabId, tab.id)
    }

    func testEmptyTargetShowsEmptyStateWithoutVisualHandoff() throws {
        let tabManager = BrowserManager()
        let space = Space(name: "Empty", profileId: UUID())
        tabManager.spaceStateOwner.replaceSpaces([space])
        let windowState = BrowserWindowState()
        tabManager.tabResidenceAuthority.establishResidenceSession(
            on: windowState
        )
        tabManager.windowRegistry.register(windowState)
        let handoff = BrowserWindowSpaceSelectionHandoff(
            tabContext: tabManager.shellRuntime.windowTabs,
            selection: tabManager.browserTabSelection,
            visuals: tabManager.shellRuntime.windowVisuals
        )

        let target = handoff.resolveTarget(for: space, in: windowState)
        handoff.present(target, in: windowState)

        XCTAssertNil(target.preferredTab)
        XCTAssertNil(windowState.currentTabId)
    }

    private func makeTab(in space: Space) -> Tab {
        Tab(
            url: URL(string: "https://space-selection.example")
                ?? URL(fileURLWithPath: "/"),
            name: "Selection",
            spaceId: space.id,
            loadsCachedFaviconOnInit: false
        )
    }
}
