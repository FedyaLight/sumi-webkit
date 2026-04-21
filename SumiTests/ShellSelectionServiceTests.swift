import XCTest
@testable import Sumi

@MainActor
final class ShellSelectionServiceTests: XCTestCase {
    func testDefaultTabUsesSumiEmptySurface() {
        let tab = Tab()

        XCTAssertEqual(tab.url, SumiSurface.emptyTabURL)
        XCTAssertTrue(tab.representsSumiEmptySurface)
    }

    func testCurrentTabRejectsLegacyPinnedSelection() {
        let service = ShellSelectionService { _ in (nil, nil) }
        let space = Space(name: "Personal")
        let legacyPinned = Tab(url: URL(string: "https://legacy.example")!, name: "Legacy", spaceId: space.id, index: 0)
        legacyPinned.isSpacePinned = true
        let regular = Tab(url: URL(string: "https://regular.example")!, name: "Regular", spaceId: space.id, index: 1)
        space.activeTabId = regular.id

        let store = FakeShellSelectionTabStore(
            spaces: [space],
            allTabs: [legacyPinned, regular],
            tabsBySpace: [space.id: [regular]]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentTabId = legacyPinned.id

        let resolved = service.currentTab(for: windowState, tabStore: store)
        XCTAssertEqual(resolved?.id, regular.id)
    }

    func testPreferredTabForSpaceSkipsLegacyPinnedActiveTabId() {
        let service = ShellSelectionService { _ in (nil, nil) }
        let space = Space(name: "Work")
        let legacyPinned = Tab(url: URL(string: "https://legacy.example")!, name: "Legacy", spaceId: space.id, index: 0)
        legacyPinned.isSpacePinned = true
        let regular = Tab(url: URL(string: "https://regular.example")!, name: "Regular", spaceId: space.id, index: 1)
        space.activeTabId = legacyPinned.id

        let store = FakeShellSelectionTabStore(
            spaces: [space],
            allTabs: [legacyPinned, regular],
            tabsBySpace: [space.id: [regular]]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id

        let resolved = service.preferredTabForSpace(space, in: windowState, tabStore: store)
        XCTAssertEqual(resolved?.id, regular.id)
    }

    func testTabsForDisplayExcludesLegacyPinnedTabs() {
        let service = ShellSelectionService { _ in (nil, nil) }
        let space = Space(name: "Docs")
        let legacyPinned = Tab(url: URL(string: "https://legacy.example")!, name: "Legacy", spaceId: space.id, index: 0)
        legacyPinned.isSpacePinned = true
        let regular = Tab(url: URL(string: "https://regular.example")!, name: "Regular", spaceId: space.id, index: 1)

        let store = FakeShellSelectionTabStore(
            spaces: [space],
            allTabs: [legacyPinned, regular],
            tabsBySpace: [space.id: [regular]]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id

        let displayed = service.tabsForDisplay(in: windowState, tabStore: store)
        XCTAssertEqual(displayed.map(\.id), [regular.id])
    }

    func testTabsForWebExtensionWindowIncludesCurrentTabWhenDisplayListMissesIt() {
        let service = ShellSelectionService { _ in (nil, nil) }
        let space = Space(name: "Video")
        let staleRegular = Tab(
            url: URL(string: "https://stale.example")!,
            name: "Stale",
            spaceId: space.id,
            index: 0
        )
        let current = Tab(
            url: URL(string: "https://www.youtube.com/watch?v=123")!,
            name: "YouTube",
            spaceId: space.id,
            index: 1
        )

        let store = FakeShellSelectionTabStore(
            spaces: [space],
            allTabs: [staleRegular, current],
            tabsBySpace: [space.id: [staleRegular]]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentTabId = current.id

        let displayed = service.tabsForWebExtensionWindow(
            in: windowState,
            tabStore: store
        )

        XCTAssertEqual(displayed.map(\.id), [staleRegular.id, current.id])
    }

    func testTabsForWebExtensionWindowIncludesSplitTabsOutsideCurrentSpace() {
        let leftSpace = Space(name: "Left")
        let rightSpace = Space(name: "Right")
        let leftTab = Tab(
            url: URL(string: "https://left.example")!,
            name: "Left",
            spaceId: leftSpace.id,
            index: 0
        )
        let splitTab = Tab(
            url: URL(string: "https://www.youtube.com/watch?v=123")!,
            name: "YouTube",
            spaceId: rightSpace.id,
            index: 0
        )

        let service = ShellSelectionService { _ in
            (left: leftTab.id, right: splitTab.id)
        }
        let store = FakeShellSelectionTabStore(
            spaces: [leftSpace, rightSpace],
            allTabs: [leftTab, splitTab],
            tabsBySpace: [
                leftSpace.id: [leftTab],
                rightSpace.id: [splitTab],
            ]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = leftSpace.id
        windowState.currentTabId = leftTab.id

        let displayed = service.tabsForWebExtensionWindow(
            in: windowState,
            tabStore: store
        )

        XCTAssertEqual(displayed.map(\.id), [leftTab.id, splitTab.id])
    }
}

@MainActor
private final class FakeShellSelectionTabStore: ShellSelectionTabStore {
    var currentTab: Tab?
    var spaces: [Space]

    private let allTabsValue: [Tab]
    private let tabsBySpace: [UUID: [Tab]]
    private let shortcutPins: [UUID: ShortcutPin]

    init(
        spaces: [Space],
        allTabs: [Tab],
        tabsBySpace: [UUID: [Tab]],
        shortcutPins: [UUID: ShortcutPin] = [:],
        currentTab: Tab? = nil
    ) {
        self.spaces = spaces
        self.allTabsValue = allTabs
        self.tabsBySpace = tabsBySpace
        self.shortcutPins = shortcutPins
        self.currentTab = currentTab
    }

    func allTabs() -> [Tab] {
        allTabsValue
    }

    func tab(for id: UUID) -> Tab? {
        allTabsValue.first(where: { $0.id == id })
    }

    func tabs(in space: Space) -> [Tab] {
        tabsBySpace[space.id] ?? []
    }

    func shortcutPin(by id: UUID) -> ShortcutPin? {
        shortcutPins[id]
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        nil
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        []
    }

    func shortcutLiveTab(for pinId: UUID, in windowId: UUID) -> Tab? {
        nil
    }

    func activateShortcutPin(_ pin: ShortcutPin, in windowId: UUID, currentSpaceId: UUID?) -> Tab {
        XCTFail("Shortcut activation was not expected in this test")
        return Tab(url: pin.launchURL, name: pin.title, spaceId: currentSpaceId, index: 0)
    }
}
