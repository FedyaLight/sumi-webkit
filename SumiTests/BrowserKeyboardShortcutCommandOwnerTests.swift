import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserKeyboardShortcutCommandOwnerTests: XCTestCase {
    func testTabCyclingSelectsRelativeIndexAndWraps() {
        let windowState = BrowserWindowState()
        let first = makeTab("https://first.example")
        let second = makeTab("https://second.example")
        let third = makeTab("https://third.example")
        var currentTab = second
        var selectedTabIds: [UUID] = []
        let owner = makeOwner(
            activeWindow: { windowState },
            tabsForDisplay: { _ in [first, second, third] },
            currentTab: { _ in currentTab },
            selectTab: { tab, _ in
                selectedTabIds.append(tab.id)
                currentTab = tab
            }
        )

        owner.selectNextTabInActiveWindow()
        owner.selectNextTabInActiveWindow()
        owner.selectPreviousTabInActiveWindow()

        XCTAssertEqual(selectedTabIds, [third.id, first.id, third.id])
    }

    func testSelectByIndexAndLastUseVisibleTabsForActiveWindow() {
        let windowState = BrowserWindowState()
        let first = makeTab("https://first.example")
        let second = makeTab("https://second.example")
        var selectedTabIds: [UUID] = []
        let owner = makeOwner(
            activeWindow: { windowState },
            tabsForDisplay: { _ in [first, second] },
            selectTab: { tab, _ in
                selectedTabIds.append(tab.id)
            }
        )

        owner.selectTabByIndexInActiveWindow(1)
        owner.selectTabByIndexInActiveWindow(4)
        owner.selectLastTabInActiveWindow()

        XCTAssertEqual(selectedTabIds, [second.id, second.id])
    }

    func testSplitLayoutUpdatesExistingSplitWithoutEnteringNewSplit() {
        let windowState = BrowserWindowState()
        var events: [String] = []
        let owner = makeOwner(
            activeWindow: { windowState },
            isSplit: { _ in true },
            setSplitLayoutKind: { layoutKind, windowId in
                events.append("layout:\(layoutKind.rawValue):\(windowId == windowState.id)")
            },
            enterSplitWithTab: { _, _ in
                events.append("enter")
            }
        )

        owner.setActiveSplitLayout(.grid)

        XCTAssertEqual(events, ["layout:grid:true"])
    }

    func testSplitLayoutCreatesSplitFromCurrentWebTabBeforeApplyingLayout() {
        let windowState = BrowserWindowState()
        let tab = makeTab("https://example.com")
        var events: [String] = []
        let owner = makeOwner(
            activeWindow: { windowState },
            currentTab: { _ in tab },
            isSplit: { _ in false },
            setSplitLayoutKind: { layoutKind, _ in
                events.append("layout:\(layoutKind.rawValue)")
            },
            enterSplitWithTab: { enteredTab, _ in
                events.append("enter:\(enteredTab.id == tab.id)")
            }
        )

        owner.setActiveSplitLayout(.vertical)

        XCTAssertEqual(events, ["enter:true", "layout:vertical"])
    }

    func testSpaceCyclingWrapsThroughSpaces() {
        let firstSpace = Space(name: "First")
        let secondSpace = Space(name: "Second")
        let thirdSpace = Space(name: "Third")
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = thirdSpace.id
        var selectedSpaceIds: [UUID] = []
        let owner = makeOwner(
            activeWindow: { windowState },
            spaces: { [firstSpace, secondSpace, thirdSpace] },
            setActiveSpace: { space, _ in
                selectedSpaceIds.append(space.id)
                windowState.currentSpaceId = space.id
            }
        )

        owner.selectNextSpaceInActiveWindow()
        owner.selectPreviousSpaceInActiveWindow()

        XCTAssertEqual(selectedSpaceIds, [firstSpace.id, thirdSpace.id])
    }

    func testExpandAllFoldersUsesActiveWindowCurrentSpaceAndPersists() {
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        windowState.currentSpaceId = spaceId
        var openedSpaceIds: [UUID] = []
        var persistedWindowIds: [UUID] = []
        let owner = makeOwner(
            activeWindow: { windowState },
            setAllFoldersOpen: { isOpen, openedSpaceId in
                if isOpen {
                    openedSpaceIds.append(openedSpaceId)
                }
            },
            persistWindowSession: { windowState in
                persistedWindowIds.append(windowState.id)
            }
        )

        owner.expandAllFoldersInSidebar()

        XCTAssertEqual(openedSpaceIds, [spaceId])
        XCTAssertEqual(persistedWindowIds, [windowState.id])
    }

    func testReaderModeUsesActivePageWebViewOrWindowFallback() async {
        let windowState = BrowserWindowState()
        let tab = makeTab("https://reader.example")
        let fallbackWebView = WKWebView()
        var toggledTabId: UUID?
        var toggledWebView: WKWebView?
        let owner = makeOwner(
            activeWindow: { windowState },
            activePageTab: { tab },
            activePageWebView: { nil },
            webView: { requestedTabId, requestedWindowId in
                requestedTabId == tab.id && requestedWindowId == windowState.id ? fallbackWebView : nil
            },
            toggleReaderMode: { webView, tab in
                toggledWebView = webView
                toggledTabId = tab.id
            }
        )

        owner.toggleReaderModeInActiveWindow()
        await Task.yield()

        XCTAssertIdentical(toggledWebView, fallbackWebView)
        XCTAssertEqual(toggledTabId, tab.id)
    }

    private func makeOwner(
        activeWindow: @escaping @MainActor () -> BrowserWindowState? = { nil },
        createNewTab: @escaping @MainActor () -> Void = {},
        openNewTabOrFloatingBar: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
        tabsForDisplay: @escaping @MainActor (BrowserWindowState) -> [Tab] = { _ in [] },
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab? = { _ in nil },
        selectTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void = { _, _ in },
        isSplit: @escaping @MainActor (UUID) -> Bool = { _ in false },
        setSplitLayoutKind: @escaping @MainActor (SplitLayoutKind, UUID) -> Void = { _, _ in },
        enterSplitWithTab: @escaping @MainActor (Tab, BrowserWindowState) -> Void = { _, _ in },
        unsplitActiveGroup: @escaping @MainActor (UUID) -> Void = { _ in },
        createEmptySplit: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
        spaces: @escaping @MainActor () -> [Space] = { [] },
        setActiveSpace: @escaping @MainActor (Space, BrowserWindowState) -> Void = { _, _ in },
        setAllFoldersOpen: @escaping @MainActor (Bool, UUID) -> Void = { _, _ in },
        persistWindowSession: @escaping @MainActor (BrowserWindowState) -> Void = { _ in },
        activePageTab: @escaping @MainActor () -> Tab? = { nil },
        activePageWebView: @escaping @MainActor () -> WKWebView? = { nil },
        webView: @escaping @MainActor (UUID, UUID) -> WKWebView? = { _, _ in nil },
        toggleReaderMode: @escaping @MainActor (WKWebView, Tab) async -> Void = { _, _ in }
    ) -> BrowserKeyboardShortcutCommandOwner {
        BrowserKeyboardShortcutCommandOwner(
            dependencies: BrowserKeyboardShortcutCommandOwner.Dependencies(
                activeWindow: activeWindow,
                createNewTab: createNewTab,
                openNewTabOrFloatingBar: openNewTabOrFloatingBar,
                tabsForDisplay: tabsForDisplay,
                currentTab: currentTab,
                selectTab: selectTab,
                isSplit: isSplit,
                setSplitLayoutKind: setSplitLayoutKind,
                enterSplitWithTab: enterSplitWithTab,
                unsplitActiveGroup: unsplitActiveGroup,
                createEmptySplit: createEmptySplit,
                spaces: spaces,
                setActiveSpace: setActiveSpace,
                setAllFoldersOpen: setAllFoldersOpen,
                persistWindowSession: persistWindowSession,
                activePageTab: activePageTab,
                activePageWebView: activePageWebView,
                webView: webView,
                toggleReaderMode: toggleReaderMode
            )
        )
    }

    private func makeTab(_ url: String) -> Tab {
        Tab(
            url: URL(string: url)!,
            name: url,
            loadsCachedFaviconOnInit: false
        )
    }
}
