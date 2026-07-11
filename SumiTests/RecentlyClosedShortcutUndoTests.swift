import XCTest

@testable import Sumi

@MainActor
final class RecentlyClosedShortcutUndoTests: XCTestCase {
    func testUndoCloseTabRestoresRegularTab() {
        let harness = makeHarness()
        let tab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://regular.example",
            in: harness.space
        )
        harness.windowState.currentTabId = tab.id

        harness.browserManager.tabLifecycleService.closeOrchestration.closeTab(tab, in: harness.windowState)
        XCTAssertTrue(harness.browserManager.tabManager.regularTabCollectionOwner.tabs(in: harness.space).isEmpty)

        harness.browserManager.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()

        let restored = harness.browserManager.tabManager.regularTabCollectionOwner.tabs(in: harness.space).first
        XCTAssertEqual(restored?.url, URL(string: "https://regular.example")!)
        XCTAssertEqual(harness.windowState.currentTabId, restored?.id)
    }

    func testUndoCloseTabRestoresSpacePinnedLiveInstanceWhenLauncherStillExists() throws {
        let harness = makeHarness()
        let pin = try insertSpacePinnedLauncher(in: harness)
        let liveTab = harness.browserManager.tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )
        let driftedURL = try XCTUnwrap(URL(string: "https://pinned.example/current"))
        liveTab.url = driftedURL
        liveTab.name = "Current pinned page"
        liveTab.canGoBack = true
        liveTab.canGoForward = true
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = pin.role

        harness.browserManager.tabLifecycleService.closeOrchestration.closeTab(liveTab, in: harness.windowState)
        XCTAssertNil(harness.browserManager.tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))

        harness.browserManager.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()

        let restored = try XCTUnwrap(
            harness.browserManager.tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id)
        )
        XCTAssertEqual(restored.shortcutPinId, pin.id)
        XCTAssertEqual(restored.url, driftedURL)
        XCTAssertEqual(restored.name, "Current pinned page")
        XCTAssertTrue(restored.canGoBack)
        XCTAssertTrue(restored.canGoForward)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
    }

    func testUndoCloseTabRestoresLauncherWhenSpacePinnedLauncherWasDeletedAfterLiveClose() throws {
        let harness = makeHarness()
        let pin = try insertSpacePinnedLauncher(in: harness)
        let liveTab = harness.browserManager.tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = pin.role

        harness.browserManager.tabLifecycleService.closeOrchestration.closeTab(liveTab, in: harness.windowState)
        harness.browserManager.tabManager.shortcutPinCommandOwner.removeShortcutPin(pin)
        XCTAssertNil(harness.browserManager.tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))

        harness.browserManager.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()

        let restoredPin = try XCTUnwrap(harness.browserManager.tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
        XCTAssertEqual(restoredPin.role, .spacePinned)
        XCTAssertEqual(restoredPin.spaceId, harness.space.id)
        XCTAssertEqual(restoredPin.launchURL, pin.launchURL)
        XCTAssertNil(harness.browserManager.tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
    }

    func testUndoCloseTabRestoresDeletedEssentialLauncher() throws {
        let harness = makeHarness()
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: harness.profile.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://essential.example")),
            title: "Essential"
        )
        let inserted = try XCTUnwrap(harness.browserManager.tabManager.shortcutPinStoreOwner.insert(pin, at: 0))

        harness.browserManager.tabManager.shortcutPinCommandOwner.removeShortcutPin(inserted)
        XCTAssertTrue(harness.browserManager.tabManager.shortcutPinCollectionStateOwner.essentialPins(for: harness.profile.id).isEmpty)

        harness.browserManager.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()

        let restoredPin = try XCTUnwrap(harness.browserManager.tabManager.shortcutPinCollectionStateOwner.shortcutPin(by: inserted.id))
        XCTAssertEqual(restoredPin.role, .essential)
        XCTAssertEqual(restoredPin.profileId, harness.profile.id)
        XCTAssertEqual(restoredPin.launchURL, inserted.launchURL)
    }

    func testClosingLastRegularTabReturnsToPreviouslySelectedEssentialLiveInstance() throws {
        let harness = makeHarness()
        let pin = try insertEssentialLauncher(in: harness)
        let essentialLiveTab = harness.browserManager.tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )

        harness.browserManager.selectTab(essentialLiveTab, in: harness.windowState)

        let regularTab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://regular.example",
            in: harness.space
        )
        harness.browserManager.selectTab(regularTab, in: harness.windowState)

        XCTAssertNil(harness.windowState.currentShortcutPinId)
        XCTAssertEqual(
            harness.windowState.selectionHistory.recentSelectionItemsBySpace[harness.space.id],
            [
                .regularTab(regularTab.id),
                .shortcutPin(pin.id),
            ]
        )

        harness.browserManager.tabLifecycleService.closeOrchestration.closeTab(regularTab, in: harness.windowState)

        XCTAssertEqual(harness.windowState.currentTabId, essentialLiveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertFalse(harness.windowState.isShowingEmptyState)
    }

    func testClosingRegularTabPrefersPreviousEssentialOverOlderRegularHistory() throws {
        let harness = makeHarness()
        let olderRegularTab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://older-regular.example",
            in: harness.space
        )
        harness.browserManager.selectTab(olderRegularTab, in: harness.windowState)

        let pin = try insertEssentialLauncher(in: harness)
        let essentialLiveTab = harness.browserManager.tabManager.shortcutTabMaterializer.materialize(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )
        harness.browserManager.selectTab(essentialLiveTab, in: harness.windowState)

        let currentRegularTab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://current-regular.example",
            in: harness.space
        )
        harness.browserManager.selectTab(currentRegularTab, in: harness.windowState)

        harness.browserManager.tabLifecycleService.closeOrchestration.closeTab(currentRegularTab, in: harness.windowState)

        XCTAssertEqual(harness.windowState.currentTabId, essentialLiveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertNotNil(harness.browserManager.tabManager.tabCollectionMembershipOwner.tab(for: olderRegularTab.id))
    }

    func testClosingRegularTabUsesRecentRegularFallbackBeforeIndexNeighbor() {
        let harness = makeHarness()
        let closingTab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://closing.example",
            in: harness.space,
            activate: false
        )
        let neighborTab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://neighbor.example",
            in: harness.space,
            activate: false
        )
        let recentTab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://recent.example",
            in: harness.space,
            activate: false
        )

        harness.windowState.currentTabId = closingTab.id
        harness.windowState.selectionHistory.recentSelectionItemsBySpace[harness.space.id] = []
        harness.windowState.selectionHistory.recentRegularTabIdsBySpace[harness.space.id] = [
            recentTab.id,
            neighborTab.id,
        ]

        harness.browserManager.tabLifecycleService.closeOrchestration.closeTab(closingTab, in: harness.windowState)

        XCTAssertEqual(harness.windowState.currentTabId, recentTab.id)
        XCTAssertNil(harness.browserManager.tabManager.tabCollectionMembershipOwner.tab(for: closingTab.id))
    }

    func testClosingRegularTabUsesNextIndexNeighborWhenHistoryDoesNotMatch() {
        let harness = makeHarness()
        let previousTab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://previous.example",
            in: harness.space,
            activate: false
        )
        let closingTab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://closing.example",
            in: harness.space,
            activate: false
        )
        let nextTab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://next.example",
            in: harness.space,
            activate: false
        )

        harness.windowState.currentTabId = closingTab.id
        harness.windowState.selectionHistory.recentSelectionItemsBySpace[harness.space.id] = [
            .regularTab(closingTab.id),
        ]
        harness.windowState.selectionHistory.recentRegularTabIdsBySpace[harness.space.id] = [
            closingTab.id,
            UUID(),
        ]

        harness.browserManager.tabLifecycleService.closeOrchestration.closeTab(closingTab, in: harness.windowState)

        XCTAssertEqual(harness.windowState.currentTabId, nextTab.id)
        XCTAssertNotNil(harness.browserManager.tabManager.tabCollectionMembershipOwner.tab(for: previousTab.id))
        XCTAssertNil(harness.browserManager.tabManager.tabCollectionMembershipOwner.tab(for: closingTab.id))
    }

    func testUnloadingSpacePinnedLiveTabReturnsToPreviouslySelectedEssentialLiveInstance() throws {
        let harness = makeHarness()
        let essentialPin = try insertEssentialLauncher(in: harness)
        let essentialLiveTab = harness.browserManager.tabManager.shortcutTabMaterializer.materialize(
            essentialPin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )
        harness.browserManager.selectTab(essentialLiveTab, in: harness.windowState)

        let spacePinnedPin = try insertSpacePinnedLauncher(in: harness)
        let spacePinnedLiveTab = harness.browserManager.tabManager.shortcutTabMaterializer.materialize(
            spacePinnedPin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )
        harness.browserManager.selectTab(spacePinnedLiveTab, in: harness.windowState)

        harness.browserManager.tabLifecycleService.closeOrchestration.closeTab(spacePinnedLiveTab, in: harness.windowState)

        XCTAssertEqual(harness.windowState.currentTabId, essentialLiveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, essentialPin.id)
        XCTAssertFalse(harness.windowState.isShowingEmptyState)
    }

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.bindTestWebViewCoordinator()
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaceStateOwner.replaceSpaces([space])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(space)

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return Harness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            windowState: windowState,
            profile: profile,
            space: space
        )
    }

    private func insertSpacePinnedLauncher(in harness: Harness) throws -> ShortcutPin {
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: harness.space.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://pinned.example/launch")),
            title: "Pinned"
        )
        return try XCTUnwrap(harness.browserManager.tabManager.shortcutPinStoreOwner.insert(pin, at: 0))
    }

    private func insertEssentialLauncher(in harness: Harness) throws -> ShortcutPin {
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: harness.profile.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://essential.example/launch")),
            title: "Essential"
        )
        return try XCTUnwrap(harness.browserManager.tabManager.shortcutPinStoreOwner.insert(pin, at: 0))
    }

    private struct Harness {
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let windowState: BrowserWindowState
        let profile: Profile
        let space: Space
    }
}
