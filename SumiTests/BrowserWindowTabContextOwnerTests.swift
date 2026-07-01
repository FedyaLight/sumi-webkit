import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowTabContextOwnerTests: XCTestCase {
    func testCurrentTabIsNilWhileInitialSessionResolutionIsPending() {
        let space = Space(name: "Work")
        let tab = makeTab("https://pending.example", spaceId: space.id)
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowState.currentSpaceId = space.id
        windowState.currentTabId = tab.id
        let harness = BrowserWindowTabContextOwnerHarness(
            spaces: [space],
            allTabs: [tab],
            tabsBySpace: [space.id: [tab]],
            windows: [windowState]
        )
        let owner = harness.makeOwner()

        XCTAssertNil(owner.currentTab(for: windowState))
    }

    func testCurrentTabResolvesIncognitoEphemeralTab() {
        let tab = makeTab("https://private.example")
        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        windowState.ephemeralTabs = [tab]
        windowState.currentTabId = tab.id
        let harness = BrowserWindowTabContextOwnerHarness(windows: [windowState])
        let owner = harness.makeOwner()

        XCTAssertIdentical(owner.currentTab(for: windowState), tab)
    }

    func testWindowStateContainingTabChecksRegularShortcutAndSplitMembership() {
        let regularTab = makeTab("https://regular.example")
        let shortcutTab = makeTab("https://shortcut.example")
        let splitTab = makeTab("https://split.example")
        let regularWindow = BrowserWindowState()
        regularWindow.currentTabId = regularTab.id
        let shortcutWindow = BrowserWindowState()
        let splitWindow = BrowserWindowState()
        let harness = BrowserWindowTabContextOwnerHarness(
            allTabs: [regularTab, shortcutTab, splitTab],
            windows: [regularWindow, shortcutWindow, splitWindow],
            liveShortcutTabsByWindowId: [shortcutWindow.id: [shortcutTab]],
            visibleSplitTabIdsByWindowId: [splitWindow.id: [splitTab.id]]
        )
        let owner = harness.makeOwner()

        XCTAssertIdentical(owner.windowState(containing: regularTab), regularWindow)
        XCTAssertIdentical(owner.windowState(containing: shortcutTab), shortcutWindow)
        XCTAssertIdentical(owner.windowState(containing: splitTab), splitWindow)
    }

    func testWindowStateContainingTabChecksIncognitoEphemeralTabs() {
        let tab = makeTab("https://private.example")
        let incognitoWindow = BrowserWindowState()
        incognitoWindow.isIncognito = true
        incognitoWindow.ephemeralTabs = [tab]
        let harness = BrowserWindowTabContextOwnerHarness(windows: [incognitoWindow])
        let owner = harness.makeOwner()

        XCTAssertIdentical(owner.windowState(containing: tab), incognitoWindow)
    }

    func testTabsForDisplayAndDisplayedInAnyWindowUseSelectionService() {
        let displayedSpace = Space(name: "Displayed")
        let hiddenSpace = Space(name: "Hidden")
        let displayedTab = makeTab("https://displayed.example", spaceId: displayedSpace.id)
        let hiddenTab = makeTab("https://hidden.example", spaceId: hiddenSpace.id)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = displayedSpace.id
        let harness = BrowserWindowTabContextOwnerHarness(
            spaces: [displayedSpace, hiddenSpace],
            allTabs: [displayedTab, hiddenTab],
            tabsBySpace: [
                displayedSpace.id: [displayedTab],
                hiddenSpace.id: [hiddenTab],
            ],
            windows: [windowState]
        )
        let owner = harness.makeOwner()

        XCTAssertEqual(owner.tabsForDisplay(in: windowState).map(\.id), [displayedTab.id])
        XCTAssertTrue(owner.isTabDisplayedInAnyWindow(displayedTab.id))
        XCTAssertFalse(owner.isTabDisplayedInAnyWindow(hiddenTab.id))
    }

    func testWindowScopedMediaCandidateTabsIncludesLiveShortcutsAndRegularTabsOnce() {
        let space = Space(name: "Media")
        let regularTab = makeTab("https://regular.example", spaceId: space.id)
        let liveShortcutTab = makeTab("https://shortcut.example", spaceId: space.id)
        let windowState = BrowserWindowState()
        let harness = BrowserWindowTabContextOwnerHarness(
            spaces: [space],
            allTabs: [regularTab],
            tabsBySpace: [space.id: [regularTab]],
            windows: [windowState],
            liveShortcutTabsByWindowId: [windowState.id: [liveShortcutTab]]
        )
        let owner = harness.makeOwner()

        XCTAssertEqual(
            owner.windowScopedMediaCandidateTabs(in: windowState).map(\.id),
            [liveShortcutTab.id, regularTab.id]
        )
    }

    private func makeTab(_ urlString: String, spaceId: UUID? = nil) -> Tab {
        Tab(
            url: URL(string: urlString) ?? preconditionFailure("Invalid test URL"),
            name: urlString,
            spaceId: spaceId,
            loadsCachedFaviconOnInit: false
        )
    }
}

@MainActor
private final class BrowserWindowTabContextOwnerHarness {
    let selectionService = ShellSelectionService { _ in [] }
    let tabStore: FakeWindowTabContextStore
    let windows: [BrowserWindowState]
    let liveShortcutTabsByWindowId: [UUID: [Tab]]
    let visibleSplitTabIdsByWindowId: [UUID: Set<UUID>]

    init(
        spaces: [Space] = [],
        allTabs: [Tab] = [],
        tabsBySpace: [UUID: [Tab]] = [:],
        windows: [BrowserWindowState] = [],
        liveShortcutTabsByWindowId: [UUID: [Tab]] = [:],
        visibleSplitTabIdsByWindowId: [UUID: Set<UUID>] = [:]
    ) {
        self.tabStore = FakeWindowTabContextStore(
            spaces: spaces,
            allTabs: allTabs,
            tabsBySpace: tabsBySpace,
            liveShortcutTabsByWindowId: liveShortcutTabsByWindowId
        )
        self.windows = windows
        self.liveShortcutTabsByWindowId = liveShortcutTabsByWindowId
        self.visibleSplitTabIdsByWindowId = visibleSplitTabIdsByWindowId
    }

    func makeOwner() -> BrowserWindowTabContextOwner {
        BrowserWindowTabContextOwner(
            dependencies: BrowserWindowTabContextOwner.Dependencies(
                selectionService: { [weak self] in self?.selectionService },
                tabStore: { [weak self] in self?.tabStore },
                windows: { [weak self] in self?.windows ?? [] },
                liveShortcutTabs: { [weak self] windowId in
                    self?.liveShortcutTabsByWindowId[windowId] ?? []
                },
                visibleSplitTabIds: { [weak self] windowId in
                    self?.visibleSplitTabIdsByWindowId[windowId] ?? []
                }
            )
        )
    }
}

@MainActor
private final class FakeWindowTabContextStore: ShellSelectionTabStore {
    var spaces: [Space]

    private let allTabs: [Tab]
    private let tabsBySpace: [UUID: [Tab]]
    private let liveShortcutTabsByWindowId: [UUID: [Tab]]

    init(
        spaces: [Space],
        allTabs: [Tab],
        tabsBySpace: [UUID: [Tab]],
        liveShortcutTabsByWindowId: [UUID: [Tab]]
    ) {
        self.spaces = spaces
        self.allTabs = allTabs
        self.tabsBySpace = tabsBySpace
        self.liveShortcutTabsByWindowId = liveShortcutTabsByWindowId
    }

    func tab(for id: UUID) -> Tab? {
        allTabs.first { $0.id == id }
            ?? liveShortcutTabsByWindowId.values.lazy.flatMap(\.self).first { $0.id == id }
    }

    func tabs(in space: Space) -> [Tab] {
        tabsBySpace[space.id] ?? []
    }

    func shortcutPin(by _: UUID) -> ShortcutPin? {
        nil
    }

    func activeShortcutTab(for windowId: UUID) -> Tab? {
        liveShortcutTabsByWindowId[windowId]?.first
    }

    func liveShortcutTabs(in windowId: UUID) -> [Tab] {
        liveShortcutTabsByWindowId[windowId] ?? []
    }

    func shortcutLiveTab(for _: UUID, in _: UUID) -> Tab? {
        nil
    }
}
