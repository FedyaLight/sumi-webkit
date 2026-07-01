@testable import Sumi
import XCTest

@MainActor
final class ShellSelectionServiceTests: XCTestCase {
    func testDefaultTabUsesSumiEmptySurface() {
        let tab = Tab()

        XCTAssertEqual(tab.url, SumiSurface.emptyTabURL)
        XCTAssertTrue(tab.representsSumiEmptySurface)
    }

    func testCurrentTabRejectsLegacyPinnedSelectionWithoutRepairFallback() {
        let service = ShellSelectionService { _ in [] }
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

        XCTAssertNil(service.currentTab(for: windowState, tabStore: store))
        XCTAssertEqual(
            service.preferredTabForSpace(space, in: windowState, tabStore: store)?.id,
            regular.id
        )
        XCTAssertFalse(service.hasValidCurrentSelection(in: windowState, tabStore: store))
    }

    func testCurrentTabDoesNotRepairStaleSelectionToPreferredSpaceTab() {
        let service = ShellSelectionService { _ in [] }
        let space = Space(name: "Personal")
        let preferred = Tab(url: URL(string: "https://preferred.example")!, name: "Preferred", spaceId: space.id, index: 0)
        space.activeTabId = preferred.id
        let store = FakeShellSelectionTabStore(
            spaces: [space],
            allTabs: [preferred],
            tabsBySpace: [space.id: [preferred]]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentTabId = UUID()

        XCTAssertNil(service.currentTab(for: windowState, tabStore: store))
        XCTAssertEqual(
            service.preferredTabForSpace(space, in: windowState, tabStore: store)?.id,
            preferred.id
        )
    }

    func testPreferredTabForSpaceSkipsLegacyPinnedActiveTabId() {
        let service = ShellSelectionService { _ in [] }
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

    func testPreferredTabForSpaceUsesRecentRegularHistoryOrder() {
        let service = ShellSelectionService { _ in [] }
        let space = Space(name: "Research")
        let first = Tab(url: URL(string: "https://first.example")!, name: "First", spaceId: space.id, index: 0)
        let second = Tab(url: URL(string: "https://second.example")!, name: "Second", spaceId: space.id, index: 1)
        let missing = UUID()
        let store = FakeShellSelectionTabStore(
            spaces: [space],
            allTabs: [first, second],
            tabsBySpace: [space.id: [first, second]]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.recentRegularTabIdsBySpace[space.id] = [missing, second.id, first.id]

        let resolved = service.preferredTabForSpace(space, in: windowState, tabStore: store)
        XCTAssertEqual(resolved?.id, second.id)
    }

    func testSelectionTargetForSpaceActivationPreservesCurrentEssentialShortcutAcrossSpaceChange() {
        let service = ShellSelectionService { _ in [] }
        let currentSpace = Space(name: "Current")
        let targetSpace = Space(name: "Target")
        let essentialPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            index: 0,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential"
        )
        let essentialLiveTab = Tab(
            url: essentialPin.launchURL,
            name: essentialPin.title,
            index: 0
        )
        essentialLiveTab.bindToShortcutPin(essentialPin)
        let targetPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: targetSpace.id,
            index: 1,
            launchURL: URL(string: "https://selected-shortcut.example")!,
            title: "Selected Shortcut"
        )
        let targetShortcut = Tab(
            url: targetPin.launchURL,
            name: targetPin.title,
            spaceId: targetSpace.id,
            index: 0
        )
        targetShortcut.bindToShortcutPin(targetPin)
        let recentRegular = Tab(
            url: URL(string: "https://recent.example")!,
            name: "Recent",
            spaceId: targetSpace.id,
            index: 1
        )
        let store = FakeShellSelectionTabStore(
            spaces: [currentSpace, targetSpace],
            allTabs: [essentialLiveTab, targetShortcut, recentRegular],
            tabsBySpace: [targetSpace.id: [recentRegular]],
            shortcutPins: [essentialPin.id: essentialPin, targetPin.id: targetPin],
            liveShortcutTabsByPin: [
                essentialPin.id: essentialLiveTab,
                targetPin.id: targetShortcut,
            ]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = currentSpace.id
        windowState.currentTabId = essentialLiveTab.id
        windowState.selectedShortcutPinForSpace[targetSpace.id] = targetPin.id
        windowState.recentRegularTabIdsBySpace[targetSpace.id] = [recentRegular.id]

        let resolved = service.selectionTargetForSpaceActivation(
            in: targetSpace,
            windowState: windowState,
            tabStore: store
        )

        XCTAssertEqual(resolved?.id, essentialLiveTab.id)
    }

    func testSelectionTargetForSpaceActivationUsesPreferredSpaceOrderingAfterCurrentSelectionGuards() {
        let service = ShellSelectionService { _ in [] }
        let currentSpace = Space(name: "Current")
        let targetSpace = Space(name: "Target")
        let staleCurrent = Tab(
            url: URL(string: "https://stale-current.example")!,
            name: "Stale Current",
            spaceId: currentSpace.id,
            index: 0
        )
        let targetPin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: targetSpace.id,
            index: 0,
            launchURL: URL(string: "https://selected-shortcut.example")!,
            title: "Selected Shortcut"
        )
        let targetShortcut = Tab(
            url: targetPin.launchURL,
            name: targetPin.title,
            spaceId: targetSpace.id,
            index: 0
        )
        targetShortcut.bindToShortcutPin(targetPin)
        let recentRegular = Tab(
            url: URL(string: "https://recent.example")!,
            name: "Recent",
            spaceId: targetSpace.id,
            index: 1
        )
        let rememberedRegular = Tab(
            url: URL(string: "https://remembered.example")!,
            name: "Remembered",
            spaceId: targetSpace.id,
            index: 2
        )
        let store = FakeShellSelectionTabStore(
            spaces: [currentSpace, targetSpace],
            allTabs: [staleCurrent, targetShortcut, recentRegular, rememberedRegular],
            tabsBySpace: [targetSpace.id: [rememberedRegular, recentRegular]],
            shortcutPins: [targetPin.id: targetPin],
            liveShortcutTabsByPin: [targetPin.id: targetShortcut]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = currentSpace.id
        windowState.currentTabId = staleCurrent.id
        windowState.selectedShortcutPinForSpace[targetSpace.id] = targetPin.id
        windowState.recentRegularTabIdsBySpace[targetSpace.id] = [recentRegular.id]
        windowState.activeTabForSpace[targetSpace.id] = rememberedRegular.id

        let selectedShortcut = service.selectionTargetForSpaceActivation(
            in: targetSpace,
            windowState: windowState,
            tabStore: store
        )
        XCTAssertEqual(selectedShortcut?.id, targetShortcut.id)

        windowState.selectedShortcutPinForSpace[targetSpace.id] = nil

        let recentFallback = service.selectionTargetForSpaceActivation(
            in: targetSpace,
            windowState: windowState,
            tabStore: store
        )
        XCTAssertEqual(recentFallback?.id, recentRegular.id)
    }

    func testSelectionTargetForSpaceActivationSkipsSameSpaceCurrentTabDuringInitialSessionResolution() {
        let service = ShellSelectionService { _ in [] }
        let space = Space(name: "Startup")
        let staleCurrent = Tab(
            url: URL(string: "https://stale-current.example")!,
            name: "Stale Current",
            spaceId: space.id,
            index: 0
        )
        let recentRegular = Tab(
            url: URL(string: "https://recent.example")!,
            name: "Recent",
            spaceId: space.id,
            index: 1
        )
        let rememberedRegular = Tab(
            url: URL(string: "https://remembered.example")!,
            name: "Remembered",
            spaceId: space.id,
            index: 2
        )
        let store = FakeShellSelectionTabStore(
            spaces: [space],
            allTabs: [staleCurrent, recentRegular, rememberedRegular],
            tabsBySpace: [space.id: [staleCurrent, rememberedRegular, recentRegular]]
        )

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentTabId = staleCurrent.id
        windowState.isAwaitingInitialSessionResolution = true
        windowState.recentRegularTabIdsBySpace[space.id] = [recentRegular.id]
        windowState.activeTabForSpace[space.id] = rememberedRegular.id

        XCTAssertTrue(service.hasValidCurrentSelection(in: windowState, tabStore: store))

        let resolved = service.selectionTargetForSpaceActivation(
            in: space,
            windowState: windowState,
            tabStore: store
        )

        XCTAssertEqual(resolved?.id, recentRegular.id)
    }

    func testTabsForDisplayExcludesLegacyPinnedTabs() {
        let service = ShellSelectionService { _ in [] }
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
        let service = ShellSelectionService { _ in [] }
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
            [leftTab.id, splitTab.id]
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

    func testPreferredTabForWindowDoesNotActivateMissingShortcutOrUseGlobalFallbackDuringRead() {
        let service = ShellSelectionService { _ in [] }
        let fallback = Tab(
            url: URL(string: "https://fallback.example")!,
            name: "Fallback",
            index: 0
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            index: 0,
            launchURL: URL(string: "https://shortcut.example")!,
            title: "Shortcut"
        )
        let store = FakeShellSelectionTabStore(
            spaces: [],
            allTabs: [fallback],
            tabsBySpace: [:],
            shortcutPins: [pin.id: pin]
        )

        let windowState = BrowserWindowState()
        windowState.currentShortcutPinId = pin.id

        let resolved = service.preferredTabForWindow(windowState, tabStore: store)

        XCTAssertNil(resolved)
        XCTAssertEqual(store.activateShortcutPinCallCount, 0)
    }

    func testPreferredRegularTabForWindowRequiresCurrentWindowSpace() {
        let service = ShellSelectionService { _ in [] }
        let otherSpace = Space(name: "Other")
        let otherTab = Tab(
            url: URL(string: "https://other.example")!,
            name: "Other",
            spaceId: otherSpace.id,
            index: 0
        )
        let store = FakeShellSelectionTabStore(
            spaces: [otherSpace],
            allTabs: [otherTab],
            tabsBySpace: [otherSpace.id: [otherTab]]
        )

        let windowState = BrowserWindowState()

        XCTAssertNil(service.preferredRegularTabForWindow(windowState, tabStore: store))
    }

    func testPreferredTabForWindowReturnsExistingShortcutLiveTabWithoutActivating() {
        let service = ShellSelectionService { _ in [] }
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            index: 0,
            launchURL: URL(string: "https://shortcut.example")!,
            title: "Shortcut"
        )
        let liveTab = Tab(
            url: pin.launchURL,
            name: pin.title,
            index: 0
        )
        liveTab.bindToShortcutPin(pin)
        let store = FakeShellSelectionTabStore(
            spaces: [],
            allTabs: [],
            tabsBySpace: [:],
            shortcutPins: [pin.id: pin],
            liveShortcutTabsByPin: [pin.id: liveTab]
        )

        let windowState = BrowserWindowState()
        windowState.currentShortcutPinId = pin.id

        let resolved = service.preferredTabForWindow(windowState, tabStore: store)

        XCTAssertEqual(resolved?.id, liveTab.id)
        XCTAssertEqual(store.activateShortcutPinCallCount, 0)
    }
}

@MainActor
private final class FakeShellSelectionTabStore: ShellSelectionTabStore {
    var spaces: [Space]

    private let allTabsValue: [Tab]
    private let tabsBySpace: [UUID: [Tab]]
    private let shortcutPins: [UUID: ShortcutPin]
    private let liveShortcutTabsByPin: [UUID: Tab]
    private(set) var activateShortcutPinCallCount = 0

    init(
        spaces: [Space],
        allTabs: [Tab],
        tabsBySpace: [UUID: [Tab]],
        shortcutPins: [UUID: ShortcutPin] = [:],
        liveShortcutTabsByPin: [UUID: Tab] = [:]
    ) {
        self.spaces = spaces
        self.allTabsValue = allTabs
        self.tabsBySpace = tabsBySpace
        self.shortcutPins = shortcutPins
        self.liveShortcutTabsByPin = liveShortcutTabsByPin
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

    func activeShortcutTab(for _: UUID) -> Tab? {
        nil
    }

    func liveShortcutTabs(in _: UUID) -> [Tab] {
        Array(liveShortcutTabsByPin.values)
    }

    func shortcutLiveTab(for pinId: UUID, in _: UUID) -> Tab? {
        liveShortcutTabsByPin[pinId]
    }

    func activateShortcutPin(_ pin: ShortcutPin, in _: UUID, currentSpaceId: UUID?) -> Tab {
        activateShortcutPinCallCount += 1
        XCTFail("Shortcut activation was not expected in this test")
        return Tab(url: pin.launchURL, name: pin.title, spaceId: currentSpaceId, index: 0)
    }
}
