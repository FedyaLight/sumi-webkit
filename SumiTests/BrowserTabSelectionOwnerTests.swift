import XCTest

@testable import Sumi

@MainActor
final class BrowserTabSelectionOwnerTests: XCTestCase {
    func testAlreadyCurrentSelectionDoesNotRunSelectionSideEffects() {
        let owner = BrowserTabSelectionOwner()
        let spaceId = UUID()
        let tab = makeTab(spaceId: spaceId)
        let windowState = BrowserWindowState()
        windowState.currentTabId = tab.id
        windowState.currentSpaceId = spaceId
        windowState.isShowingEmptyState = false
        windowState.activeTabForSpace[spaceId] = tab.id
        windowState.recentRegularTabIdsBySpace[spaceId] = [tab.id]
        windowState.recentSelectionItemsBySpace[spaceId] = [.regularTab(tab.id)]
        let probe = ActionProbe(activeWindowId: windowState.id)

        owner.applyTabSelection(
            tab,
            in: windowState,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: true,
            loadPolicy: .immediate,
            actions: makeActions(probe: probe)
        )

        XCTAssertTrue(probe.events.isEmpty)
        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertEqual(windowState.currentSpaceId, spaceId)
        XCTAssertFalse(windowState.isShowingEmptyState)
    }

    func testRegularSelectionCoordinatesBrowserSideEffectsAndPersistence() {
        let owner = BrowserTabSelectionOwner()
        let space = Space(id: UUID(), name: "Work")
        let previousTab = makeTab(spaceId: space.id)
        let selectedTab = makeTab(spaceId: space.id)
        let windowState = BrowserWindowState()
        windowState.currentTabId = previousTab.id
        let probe = ActionProbe(activeWindowId: windowState.id)

        owner.applyTabSelection(
            selectedTab,
            in: windowState,
            updateSpaceFromTab: true,
            updateTheme: true,
            rememberSelection: true,
            persistSelection: true,
            loadPolicy: .immediate,
            actions: makeActions(
                probe: probe,
                space: space,
                tabsById: [previousTab.id: previousTab]
            )
        )

        XCTAssertEqual(windowState.currentTabId, selectedTab.id)
        XCTAssertEqual(windowState.currentSpaceId, space.id)
        XCTAssertEqual(windowState.activeTabForSpace[space.id], selectedTab.id)
        XCTAssertEqual(windowState.recentRegularTabIdsBySpace[space.id], [selectedTab.id])
        XCTAssertEqual(
            probe.events,
            [
                "nowPlayingActivated",
                "dismissFloatingBar",
                "splitSide",
                "syncSpaceContext",
                "workspaceTheme:true",
                "fetchFavicon",
                "nowPlayingRefresh",
                "updateFind",
                "prepareVisibleWebViews",
                "refreshCompositor",
                "notifyActivated:\(previousTab.id.uuidString)",
                "tabSuspension:tab-selection-changed",
                "backgroundMedia:tab-selection-changed",
                "updateActiveTabState",
                "persistWindowSession",
            ]
        )
    }

    func testShortcutSyncTracksCurrentLiveShortcutTab() {
        let owner = BrowserTabSelectionOwner()
        let spaceId = UUID()
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: spaceId,
            index: 0,
            launchURL: URL(string: "https://example.com/pinned")!,
            title: "Pinned"
        )
        let liveTab = makeTab(spaceId: spaceId)
        liveTab.bindToShortcutPin(pin)
        let windowState = BrowserWindowState()
        windowState.currentTabId = liveTab.id

        owner.syncShortcutSelectionState(
            for: windowState,
            actions: makeActions(
                probe: ActionProbe(activeWindowId: windowState.id),
                liveShortcutTabs: [liveTab]
            )
        )

        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .spacePinned)
    }

    func testEmptyStateClearsSelectionAndShowsNewTabFloatingBarWhenNoFallbackExists() {
        let owner = BrowserTabSelectionOwner()
        let space = Space(id: UUID(), name: "Empty")
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowState.currentTabId = UUID()
        windowState.currentShortcutPinId = UUID()
        windowState.currentShortcutPinRole = .spacePinned
        windowState.isShowingEmptyState = false
        let probe = ActionProbe(activeWindowId: windowState.id)

        owner.showEmptyState(
            in: windowState,
            actions: makeActions(probe: probe, space: space)
        )

        XCTAssertNil(windowState.currentTabId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertTrue(windowState.isShowingEmptyState)
        XCTAssertEqual(
            probe.events,
            [
                "updateProfileRuntimeStates",
                "clearFind",
                "refreshCompositor",
                "persistWindowSession",
                "showNewTabFloatingBar",
            ]
        )
    }

    private final class ActionProbe {
        let activeWindowId: UUID?
        var events: [String] = []

        init(activeWindowId: UUID?) {
            self.activeWindowId = activeWindowId
        }
    }

    private func makeActions(
        probe: ActionProbe,
        space: Space? = nil,
        tabsById: [UUID: Tab] = [:],
        currentTab: Tab? = nil,
        liveShortcutTabs: [Tab] = [],
        selectionTarget: Tab? = nil
    ) -> BrowserTabSelectionOwner.Actions {
        BrowserTabSelectionOwner.Actions(
            activeWindowId: { probe.activeWindowId },
            tab: { tabsById[$0] },
            currentTab: { _ in currentTab },
            liveShortcutTabs: { _ in liveShortcutTabs },
            updateActiveSplitSide: { _, _ in probe.events.append("splitSide") },
            syncWindowSpaceContext: { _, _ in probe.events.append("syncSpaceContext") },
            space: { spaceId in
                guard let space, space.id == spaceId else { return nil }
                return space
            },
            updateWorkspaceTheme: { _, _, animate in
                probe.events.append("workspaceTheme:\(animate)")
            },
            applySettingsSurfaceNavigation: { _ in probe.events.append("settingsNavigation") },
            canMaterializeNormalTabWebViewDuringStartup: { _ in true },
            markTabAccessed: { _ in probe.events.append("markTabAccessed") },
            webViewCoordinator: { nil },
            handleNativeNowPlayingTabActivated: { _ in probe.events.append("nowPlayingActivated") },
            scheduleNativeNowPlayingRefresh: { _ in probe.events.append("nowPlayingRefresh") },
            fetchVisibleFavicon: { _ in probe.events.append("fetchFavicon") },
            dismissFloatingBarAfterSelection: { _ in probe.events.append("dismissFloatingBar") },
            updateFindManagerCurrentTab: { probe.events.append("updateFind") },
            clearFindManagerCurrentTab: { probe.events.append("clearFind") },
            schedulePrepareVisibleWebViews: { _ in probe.events.append("prepareVisibleWebViews") },
            refreshCompositor: { _ in probe.events.append("refreshCompositor") },
            runtimeNotifications: BrowserTabSelectionOwner.RuntimeNotifications(
                tabActivated: { _, previousTab in
                    probe.events.append("notifyActivated:\(previousTab?.id.uuidString ?? "nil")")
                },
                tabSelectionChanged: { reason in
                    probe.events.append("tabSuspension:\(reason)")
                    probe.events.append("backgroundMedia:\(reason)")
                }
            ),
            updateActiveTabState: { _ in probe.events.append("updateActiveTabState") },
            persistWindowSession: { _ in probe.events.append("persistWindowSession") },
            selectionTargetForSpaceActivation: { _, _ in selectionTarget },
            updateProfileRuntimeStates: { _ in probe.events.append("updateProfileRuntimeStates") },
            showNewTabFloatingBar: { _ in probe.events.append("showNewTabFloatingBar") }
        )
    }

    private func makeTab(
        id: UUID = UUID(),
        spaceId: UUID?
    ) -> Tab {
        Tab(
            id: id,
            url: SumiSurface.emptyTabURL,
            name: "Tab",
            spaceId: spaceId,
            loadsCachedFaviconOnInit: false
        )
    }
}
