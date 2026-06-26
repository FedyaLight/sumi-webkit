import XCTest

@testable import Sumi

@MainActor
final class BrowserTabCloseFallbackPlannerTests: XCTestCase {
    func testRegularTabCloseUsesRecentShortcutSelectionBeforeAdjacentRegularFallback() {
        let space = Space(name: "Work")
        let closing = makeTab("Closing", spaceId: space.id, index: 0)
        let adjacent = makeTab("Adjacent", spaceId: space.id, index: 1)
        let shortcutPin = makeShortcutPin(role: .spacePinned, spaceId: space.id)
        let shortcutLiveTab = makeShortcutTab(pin: shortcutPin, spaceId: space.id)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.recentSelectionItemsBySpace[space.id] = [
            .regularTab(closing.id),
            .shortcutPin(shortcutPin.id),
            .regularTab(adjacent.id),
        ]
        let store = FakeCloseFallbackTabStore(
            spaces: [space],
            tabsBySpace: [space.id: [closing, adjacent]],
            liveShortcutTabsByPin: [shortcutPin.id: shortcutLiveTab]
        )
        let planner = BrowserTabCloseFallbackPlanner(
            selectionService: ShellSelectionService { _ in [] }
        )

        let fallback = planner.fallbackAfterClosingRegularTab(
            closing,
            in: windowState,
            tabStore: store
        )

        XCTAssertEqual(fallback?.id, shortcutLiveTab.id)
    }

    func testRegularTabCloseUsesNextAdjacentTabWhenHistoryIsStale() {
        let space = Space(name: "Work")
        let first = makeTab("First", spaceId: space.id, index: 0)
        let closing = makeTab("Closing", spaceId: space.id, index: 1)
        let next = makeTab("Next", spaceId: space.id, index: 2)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.recentRegularTabIdsBySpace[space.id] = [UUID()]
        windowState.recentSelectionItemsBySpace[space.id] = [.regularTab(UUID())]
        let store = FakeCloseFallbackTabStore(
            spaces: [space],
            tabsBySpace: [space.id: [first, closing, next]]
        )
        let planner = BrowserTabCloseFallbackPlanner(
            selectionService: ShellSelectionService { _ in [] }
        )

        let fallback = planner.fallbackAfterClosingRegularTab(
            closing,
            in: windowState,
            tabStore: store
        )

        XCTAssertEqual(fallback?.id, next.id)
    }

    func testShortcutLiveCloseUsesRecentRegularSelectionBeforePreferredRegularFallback() {
        let space = Space(name: "Work")
        let recent = makeTab("Recent", spaceId: space.id, index: 0)
        let preferred = makeTab("Preferred", spaceId: space.id, index: 1)
        space.activeTabId = preferred.id
        let shortcutPin = makeShortcutPin(role: .spacePinned, spaceId: space.id)
        let shortcutLiveTab = makeShortcutTab(pin: shortcutPin, spaceId: space.id)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.activeTabForSpace[space.id] = preferred.id
        windowState.recentSelectionItemsBySpace[space.id] = [.regularTab(recent.id)]
        let store = FakeCloseFallbackTabStore(
            spaces: [space],
            tabsBySpace: [space.id: [recent, preferred]],
            liveShortcutTabsByPin: [shortcutPin.id: shortcutLiveTab]
        )
        let planner = BrowserTabCloseFallbackPlanner(
            selectionService: ShellSelectionService { _ in [] }
        )

        let fallback = planner.fallbackAfterClosingShortcutLiveTab(
            shortcutLiveTab,
            in: windowState,
            tabStore: store
        )

        XCTAssertEqual(fallback?.id, recent.id)
    }

    func testShortcutLiveCloseFallsBackToPreferredRegularTabWhenSelectionHistoryHasNoMatch() {
        let space = Space(name: "Work")
        let remembered = makeTab("Remembered", spaceId: space.id, index: 0)
        let shortcutPin = makeShortcutPin(role: .spacePinned, spaceId: space.id)
        let shortcutLiveTab = makeShortcutTab(pin: shortcutPin, spaceId: space.id)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.activeTabForSpace[space.id] = remembered.id
        windowState.recentSelectionItemsBySpace[space.id] = [.regularTab(UUID())]
        let store = FakeCloseFallbackTabStore(
            spaces: [space],
            tabsBySpace: [space.id: [remembered]],
            liveShortcutTabsByPin: [shortcutPin.id: shortcutLiveTab]
        )
        let planner = BrowserTabCloseFallbackPlanner(
            selectionService: ShellSelectionService { _ in [] }
        )

        let fallback = planner.fallbackAfterClosingShortcutLiveTab(
            shortcutLiveTab,
            in: windowState,
            tabStore: store
        )

        XCTAssertEqual(fallback?.id, remembered.id)
    }

    private func makeTab(_ name: String, spaceId: UUID, index: Int) -> Tab {
        Tab(
            url: URL(string: "https://example.com/\(name.lowercased())")!,
            name: name,
            spaceId: spaceId,
            index: index,
            loadsCachedFaviconOnInit: false
        )
    }

    private func makeShortcutTab(pin: ShortcutPin, spaceId: UUID?) -> Tab {
        let tab = Tab(
            url: pin.launchURL,
            name: pin.title,
            spaceId: spaceId,
            index: 0,
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

@MainActor
private final class FakeCloseFallbackTabStore: ShellSelectionTabStore {
    var spaces: [Space]

    private let tabsBySpace: [UUID: [Tab]]
    private let liveShortcutTabsByPin: [UUID: Tab]

    init(
        spaces: [Space],
        tabsBySpace: [UUID: [Tab]],
        liveShortcutTabsByPin: [UUID: Tab] = [:]
    ) {
        self.spaces = spaces
        self.tabsBySpace = tabsBySpace
        self.liveShortcutTabsByPin = liveShortcutTabsByPin
    }

    func tab(for id: UUID) -> Tab? {
        tabsBySpace.values.lazy.flatMap { $0 }.first { $0.id == id }
            ?? liveShortcutTabsByPin.values.first { $0.id == id }
    }

    func tabs(in space: Space) -> [Tab] {
        tabsBySpace[space.id] ?? []
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        nil
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        nil
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        Array(liveShortcutTabsByPin.values)
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        liveShortcutTabsByPin[pinId]
    }
}
