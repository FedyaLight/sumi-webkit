import SumiDomain
import XCTest

@testable import Sumi

@MainActor
final class RecentlyClosedShortcutUndoTests: XCTestCase {
    func testUndoCloseTabRestoresRegularTab() {
        let harness = makeHarness()
        let tab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://regular.example",
            in: harness.space
        )
        harness.windowState.currentTabId = tab.id

        harness.browserManager.tabCloseOrchestration.closeTab(tab, in: harness.windowState)
        XCTAssertTrue(harness.browserManager.regularTabCollectionOwner.tabs(in: harness.space).isEmpty)

        harness.browserManager.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()

        let restored = harness.browserManager.regularTabCollectionOwner.tabs(in: harness.space).first
        XCTAssertEqual(restored?.url, URL(string: "https://regular.example")!)
        XCTAssertEqual(harness.windowState.currentTabId, restored?.id)
    }

    func testUndoCloseTabRestoresSpacePinnedLiveInstanceWhenLauncherStillExists() throws {
        let harness = makeHarness()
        let pin = try insertSpacePinnedLauncher(in: harness)
        let liveTab = harness.browserManager.shortcutTabMaterializer.materialize(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )!
        let driftedURL = try XCTUnwrap(URL(string: "https://pinned.example/current"))
        liveTab.url = driftedURL
        liveTab.name = "Current pinned page"
        liveTab.canGoBack = true
        liveTab.canGoForward = true
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = pin.role

        harness.browserManager.tabCloseOrchestration.closeTab(liveTab, in: harness.windowState)
        XCTAssertNil(harness.browserManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))

        harness.browserManager.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()

        let restored = try XCTUnwrap(
            harness.browserManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id)
        )
        XCTAssertEqual(restored.shortcutPinId, pin.id)
        XCTAssertEqual(restored.mainFrameLoads.currentIntent.targetURL, driftedURL)
        XCTAssertEqual(restored.url, pin.launchURL)
        XCTAssertEqual(restored.name, "Current pinned page")
        XCTAssertTrue(restored.canGoBack)
        XCTAssertTrue(restored.canGoForward)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
    }

    func testUndoCloseTabRestoresLauncherWhenSpacePinnedLauncherWasDeletedAfterLiveClose() throws {
        let harness = makeHarness()
        let pin = try insertSpacePinnedLauncher(in: harness)
        let liveTab = harness.browserManager.shortcutTabMaterializer.materialize(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )!
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = pin.role

        harness.browserManager.tabCloseOrchestration.closeTab(liveTab, in: harness.windowState)
        XCTAssertTrue(harness.browserManager.sidebarPinCommands.remove(pin))
        XCTAssertNil(harness.browserManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))

        harness.browserManager.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()

        let restoredPin = try XCTUnwrap(harness.browserManager.shortcutPinCollectionStateOwner.shortcutPin(by: pin.id))
        XCTAssertEqual(restoredPin.role, .spacePinned)
        XCTAssertEqual(restoredPin.spaceId, harness.space.id)
        XCTAssertEqual(restoredPin.launchURL, pin.launchURL)
        XCTAssertNil(harness.browserManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
    }

    func testUndoCloseTabRestoresDeletedFavoriteLauncher() throws {
        let harness = makeHarness()
        let pin = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: harness.profile.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://favorite.example")),
            title: "Favorite"
        )
        let inserted = try XCTUnwrap(harness.browserManager.shortcutPinStoreOwner.insert(pin, at: 0))

        XCTAssertTrue(harness.browserManager.sidebarPinCommands.remove(inserted))
        XCTAssertTrue(harness.browserManager.shortcutPinCollectionStateOwner.favoritePins(for: harness.profile.id).isEmpty)

        harness.browserManager.windowSessionBundle.sessionRecovery.reopenMostRecentClosedItem()

        let restoredPin = try XCTUnwrap(harness.browserManager.shortcutPinCollectionStateOwner.shortcutPin(by: inserted.id))
        XCTAssertEqual(restoredPin.role, .favorite)
        XCTAssertEqual(restoredPin.profileId, harness.profile.id)
        XCTAssertEqual(restoredPin.launchURL, inserted.launchURL)
    }

    func testClosingLastRegularTabReturnsToPreviouslySelectedFavoriteLiveInstance() throws {
        let harness = makeHarness()
        let pin = try insertFavoriteLauncher(in: harness)
        let favoriteLiveTab = harness.browserManager.shortcutTabMaterializer.materialize(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )!

        harness.browserManager.selectTab(favoriteLiveTab, in: harness.windowState)

        let regularTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
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

        harness.browserManager.tabCloseOrchestration.closeTab(regularTab, in: harness.windowState)

        XCTAssertEqual(harness.windowState.currentTabId, favoriteLiveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertFalse(harness.windowState.isShowingEmptyState)
    }

    func testClosingRegularTabPrefersPreviousFavoriteOverOlderRegularHistory() throws {
        let harness = makeHarness()
        let olderRegularTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://older-regular.example",
            in: harness.space
        )
        harness.browserManager.selectTab(olderRegularTab, in: harness.windowState)

        let pin = try insertFavoriteLauncher(in: harness)
        let favoriteLiveTab = harness.browserManager.shortcutTabMaterializer.materialize(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )!
        harness.browserManager.selectTab(favoriteLiveTab, in: harness.windowState)

        let currentRegularTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://current-regular.example",
            in: harness.space
        )
        harness.browserManager.selectTab(currentRegularTab, in: harness.windowState)

        harness.browserManager.tabCloseOrchestration.closeTab(currentRegularTab, in: harness.windowState)

        XCTAssertEqual(harness.windowState.currentTabId, favoriteLiveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertNotNil(harness.browserManager.tabCollectionMembershipOwner.tab(for: olderRegularTab.id))
    }

    func testClosingRegularTabUsesRecentRegularFallbackBeforeIndexNeighbor() {
        let harness = makeHarness()
        let closingTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://closing.example",
            in: harness.space,
            activate: false
        )
        let neighborTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://neighbor.example",
            in: harness.space,
            activate: false
        )
        let recentTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
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

        harness.browserManager.tabCloseOrchestration.closeTab(closingTab, in: harness.windowState)

        XCTAssertEqual(harness.windowState.currentTabId, recentTab.id)
        XCTAssertNil(harness.browserManager.tabCollectionMembershipOwner.tab(for: closingTab.id))
    }

    func testClosingRegularTabUsesNextIndexNeighborWhenHistoryDoesNotMatch() {
        let harness = makeHarness()
        let previousTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://previous.example",
            in: harness.space,
            activate: false
        )
        let closingTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://closing.example",
            in: harness.space,
            activate: false
        )
        let nextTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
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

        harness.browserManager.tabCloseOrchestration.closeTab(closingTab, in: harness.windowState)

        XCTAssertEqual(harness.windowState.currentTabId, nextTab.id)
        XCTAssertNotNil(harness.browserManager.tabCollectionMembershipOwner.tab(for: previousTab.id))
        XCTAssertNil(harness.browserManager.tabCollectionMembershipOwner.tab(for: closingTab.id))
    }

    func testUnloadingSpacePinnedLiveTabReturnsToPreviouslySelectedFavoriteLiveInstance() throws {
        let harness = makeHarness()
        let favoritePin = try insertFavoriteLauncher(in: harness)
        let favoriteLiveTab = harness.browserManager.shortcutTabMaterializer.materialize(
            favoritePin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )!
        harness.browserManager.selectTab(favoriteLiveTab, in: harness.windowState)

        let spacePinnedPin = try insertSpacePinnedLauncher(in: harness)
        let spacePinnedLiveTab = harness.browserManager.shortcutTabMaterializer.materialize(
            spacePinnedPin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )!
        harness.browserManager.selectTab(spacePinnedLiveTab, in: harness.windowState)

        harness.browserManager.tabCloseOrchestration.closeTab(spacePinnedLiveTab, in: harness.windowState)

        XCTAssertEqual(harness.windowState.currentTabId, favoriteLiveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, favoritePin.id)
        XCTAssertFalse(harness.windowState.isShowingEmptyState)
    }

    func testUnloadingCurrentShortcutRestoresWholePreviousRegularSplit()
        throws {
        let harness = makeHarness()
        let first = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split-first.example",
            in: harness.space,
            activate: false
        )
        let second = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://split-second.example",
            in: harness.space,
            activate: false
        )
        let group = try XCTUnwrap(SplitGroup.make(
            members: [
                .regularTab(first.id),
                .regularTab(second.id),
            ],
            layoutKind: .vertical,
            container: .regularTabs(spaceId: harness.space.id)
        ))
        XCTAssertTrue(
            harness.browserManager.splitGroupMutations.insert(
                group,
                persist: false
            )
        )
        harness.browserManager.selectTab(first, in: harness.windowState)

        let pin = try insertSpacePinnedLauncher(in: harness)
        let current = try XCTUnwrap(
            harness.browserManager.shortcutTabMaterializer.materialize(
                pin,
                in: harness.windowState.id,
                currentSpaceId: harness.space.id
            )
        )
        harness.browserManager.selectTab(current, in: harness.windowState)

        harness.browserManager.tabCloseOrchestration.closeTab(
            current,
            in: harness.windowState
        )

        XCTAssertEqual(harness.windowState.currentTabId, first.id)
        XCTAssertEqual(harness.windowState.splitSelection?.groupID, group.id)
        guard case .ready(let presentation) =
            harness.browserManager.splitQuery.resolution(
                in: harness.windowState.id
            )
        else {
            return XCTFail("Expected the previous split group presentation")
        }
        XCTAssertEqual(presentation.groupID, group.id)
        XCTAssertEqual(Set(presentation.visibleTabIDs), [first.id, second.id])
        XCTAssertEqual(presentation.activeTabID, first.id)
    }

    private func makeHarness() -> Harness {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
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
        return try XCTUnwrap(harness.browserManager.shortcutPinStoreOwner.insert(pin, at: 0))
    }

    private func insertFavoriteLauncher(in harness: Harness) throws -> ShortcutPin {
        let pin = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: harness.profile.id,
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://favorite.example/launch")),
            title: "Favorite"
        )
        return try XCTUnwrap(harness.browserManager.shortcutPinStoreOwner.insert(pin, at: 0))
    }

    private struct Harness {
        let browserManager: BrowserManager
        let windowRegistry: WindowRegistry
        let windowState: BrowserWindowState
        let profile: Profile
        let space: Space
    }
}
