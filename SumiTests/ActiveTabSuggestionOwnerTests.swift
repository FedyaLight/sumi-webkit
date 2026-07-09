//
//  ActiveTabSuggestionOwnerTests.swift
//  SumiTests
//
//

import XCTest

@testable import Sumi

@MainActor
final class ActiveTabSuggestionOwnerTests: XCTestCase {
    func testRanksTabsBySelectionHistoryOrder() {
        let older = makeTab(name: "Older", url: "https://a.example")
        let newer = makeTab(name: "Newer", url: "https://b.example")
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        windowState.currentSpaceId = spaceId
        windowState.selectionHistory.recentSelectionItemsBySpace[spaceId] = [
            .regularTab(newer.id),
            .regularTab(older.id),
        ]

        let owner = makeOwner(allTabs: [older, newer])
        let suggestions = owner.suggestions(for: windowState)

        XCTAssertEqual(suggestions.map(\.text), ["Newer", "Older"])
    }

    func testFallsBackToLastSelectedAtWhenNoSelectionHistoryRank() {
        let older = makeTab(name: "Older", url: "https://a.example")
        older.suspensionStateOwner.lastSelectedAt = Date(timeIntervalSince1970: 1)
        let newer = makeTab(name: "Newer", url: "https://b.example")
        newer.suspensionStateOwner.lastSelectedAt = Date(timeIntervalSince1970: 2)
        let windowState = BrowserWindowState()

        let owner = makeOwner(allTabs: [older, newer])
        let suggestions = owner.suggestions(for: windowState)

        XCTAssertEqual(suggestions.map(\.text), ["Newer", "Older"])
    }

    func testExcludesTabsVisibleInASplit() {
        let visible = makeTab(name: "Visible", url: "https://a.example")
        let hidden = makeTab(name: "Hidden", url: "https://b.example")
        let windowState = BrowserWindowState()

        let owner = makeOwner(allTabs: [visible, hidden], visibleSplitTabIds: [visible.id])
        let suggestions = owner.suggestions(for: windowState)

        XCTAssertEqual(suggestions.map(\.text), ["Hidden"])
    }

    func testIncludesLiveShortcutTabsForTheWindow() {
        let regular = makeTab(name: "Regular", url: "https://a.example")
        let shortcut = makeTab(name: "Shortcut", url: "https://shortcut.example")
        let windowState = BrowserWindowState()

        let owner = makeOwner(allTabs: [regular], liveShortcutTabs: [windowState.id: [shortcut]])
        let suggestions = owner.suggestions(for: windowState)

        XCTAssertTrue(suggestions.contains { $0.text == "Shortcut" })
    }

    func testIncognitoWindowOnlyUsesEphemeralTabs() {
        let regular = makeTab(name: "Regular", url: "https://a.example")
        let ephemeral = makeTab(name: "Ephemeral", url: "https://b.example")
        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        windowState.ephemeralTabs = [ephemeral]

        let owner = makeOwner(allTabs: [regular])
        let suggestions = owner.suggestions(for: windowState)

        XCTAssertEqual(suggestions.map(\.text), ["Ephemeral"])
    }

    func testShortcutPinSelectionIsResolvedToLiveTabRank() {
        let regular = makeTab(name: "Regular", url: "https://a.example")
        let shortcut = makeTab(name: "Shortcut", url: "https://shortcut.example")
        let pinId = UUID()
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        windowState.currentSpaceId = spaceId
        windowState.selectionHistory.recentSelectionItemsBySpace[spaceId] = [.shortcutPin(pinId)]

        let owner = makeOwner(
            allTabs: [regular],
            liveShortcutTabs: [windowState.id: [shortcut]],
            shortcutLiveTab: [pinId: shortcut]
        )
        let suggestions = owner.suggestions(for: windowState)

        XCTAssertEqual(suggestions.first?.text, "Shortcut")
    }

    // MARK: - Helpers

    private func makeOwner(
        allTabs: [Tab],
        liveShortcutTabs: [UUID: [Tab]] = [:],
        shortcutLiveTab: [UUID: Tab] = [:],
        visibleSplitTabIds: Set<UUID> = []
    ) -> ActiveTabSuggestionOwner {
        ActiveTabSuggestionOwner(
            allTabsForCurrentProfile: { allTabs },
            liveShortcutTabs: { windowId in liveShortcutTabs[windowId] ?? [] },
            shortcutLiveTab: { pinId, _ in shortcutLiveTab[pinId] },
            visibleSplitTabIds: { _ in visibleSplitTabIds }
        )
    }

    private func makeTab(name: String, url: String) -> Tab {
        let tab = Tab(url: URL(string: url)!)
        tab.name = name
        return tab
    }
}
