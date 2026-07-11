import Foundation
@testable import Sumi
import XCTest

@MainActor
final class BrowserWindowSpaceSelectionHandoffTests: XCTestCase {
    func testResolvedTabIsSelectedBeforeImmediateVisualHandoff() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = Space(name: "Target", profileId: UUID())
        let tab = makeTab(in: space)
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.regularTabCollectionStateOwner.replaceTabsBySpace([
            space.id: [tab],
        ])
        let windowState = BrowserWindowState()
        var events: [String] = []
        let handoff = BrowserWindowSpaceSelectionHandoff(
            tabContext: makeTabContext(
                tabManager: tabManager,
                windows: [windowState]
            ),
            applyTabSelection: { selectedTab, selectedWindow in
                selectedWindow.currentTabId = selectedTab.id
                events.append("select")
            },
            performImmediateVisualHandoff: { _ in
                events.append("visual-handoff")
            },
            showEmptyState: { _ in
                events.append("empty")
            }
        )

        let target = handoff.resolveTarget(for: space, in: windowState)
        handoff.present(target, in: windowState)

        XCTAssertIdentical(target.preferredTab, tab)
        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertEqual(events, ["select", "visual-handoff"])
    }

    func testEmptyTargetShowsEmptyStateWithoutVisualHandoff() throws {
        let tabManager = try makeInMemoryTabManager()
        let space = Space(name: "Empty", profileId: UUID())
        tabManager.spaceStateOwner.replaceSpaces([space])
        let windowState = BrowserWindowState()
        var events: [String] = []
        let handoff = BrowserWindowSpaceSelectionHandoff(
            tabContext: makeTabContext(
                tabManager: tabManager,
                windows: [windowState]
            ),
            applyTabSelection: { _, _ in events.append("select") },
            performImmediateVisualHandoff: { _ in
                events.append("visual-handoff")
            },
            showEmptyState: { _ in events.append("empty") }
        )

        let target = handoff.resolveTarget(for: space, in: windowState)
        handoff.present(target, in: windowState)

        XCTAssertNil(target.preferredTab)
        XCTAssertEqual(events, ["empty"])
    }

    private func makeTabContext(
        tabManager: TabManager,
        windows: [BrowserWindowState]
    ) -> BrowserWindowTabContext {
        let selection = ShellSelectionService { _ in [] }
        return BrowserWindowTabContext(
            selectionService: { selection },
            tabStore: { tabManager.runtimeStore },
            windows: { windows },
            liveShortcutTabs: { windowId in
                tabManager.runtimeStore.liveShortcutTabs(in: windowId)
            },
            visibleSplitTabIds: { _ in [] }
        )
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
