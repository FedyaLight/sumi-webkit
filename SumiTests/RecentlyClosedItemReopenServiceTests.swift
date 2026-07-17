import XCTest

@testable import Sumi

@MainActor
final class RecentlyClosedItemReopenServiceTests: XCTestCase {
    func testReopenTabItemRemovesItFromHistoryAndConsumesRestoreOffer() throws {
        let harness = makeHarness()
        let closedTab = Tab(
            url: try XCTUnwrap(URL(string: "https://closed.example")),
            name: "Closed"
        )
        harness.recentlyClosedManager.captureClosedTab(
            closedTab,
            sourceSpaceId: harness.space.id,
            currentURL: nil,
            canGoBack: false,
            canGoForward: false
        )
        let item = try XCTUnwrap(harness.recentlyClosedManager.mostRecentItem)

        harness.service.reopenMostRecentItem()

        XCTAssertNil(harness.recentlyClosedManager.mostRecentItem)
        XCTAssertTrue(harness.startupRestore.didConsumeRestoreOffer)
        XCTAssertFalse(harness.recentlyClosedManager.items.contains { $0.id == item.id })
        XCTAssertFalse(
            harness.browserManager.regularTabCollectionOwner
                .tabs(in: harness.space).isEmpty
        )
    }

    func testFailedTabRestoreKeepsHistoryItemAndRestoreOffer() throws {
        let harness = makeHarness()
        let orphanTab = Tab(
            url: try XCTUnwrap(URL(string: "https://orphan.example")),
            name: "Orphan"
        )
        harness.recentlyClosedManager.captureClosedTab(
            orphanTab,
            sourceSpaceId: nil,
            currentURL: nil,
            canGoBack: false,
            canGoForward: false
        )
        let item = try XCTUnwrap(harness.recentlyClosedManager.mostRecentItem)

        harness.service.reopenMostRecentItem()

        XCTAssertEqual(harness.recentlyClosedManager.mostRecentItem?.id, item.id)
        XCTAssertFalse(harness.startupRestore.didConsumeRestoreOffer)
    }

    func testFailedLauncherRestoreKeepsHistoryItem() throws {
        let harness = makeHarness()
        let orphanEssentialPin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: UUID(),
            index: 0,
            launchURL: try XCTUnwrap(URL(string: "https://essential.example")),
            title: "Essential"
        )
        harness.recentlyClosedManager.captureDeletedShortcutLauncher(orphanEssentialPin)
        let item = try XCTUnwrap(harness.recentlyClosedManager.mostRecentItem)

        harness.service.reopen(item)

        XCTAssertEqual(harness.recentlyClosedManager.mostRecentItem?.id, item.id)
        XCTAssertNil(
            harness.browserManager.shortcutPinCollectionStateOwner
                .shortcutPin(by: orphanEssentialPin.id)
        )
        XCTAssertFalse(harness.startupRestore.didConsumeRestoreOffer)
    }

    func testWindowItemIsRemovedOnlyAfterReopenReportsSuccess() async throws {
        let harness = makeHarness()
        let sessionWindowId = UUID()
        harness.recentlyClosedManager.captureClosedWindow(
            sessionWindowId: sessionWindowId,
            title: "Window",
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let item = try XCTUnwrap(harness.recentlyClosedManager.mostRecentItem)

        harness.service.reopen(item)

        XCTAssertEqual(
            harness.recentlyClosedManager.mostRecentItem?.id,
            item.id,
            "Window item must stay in history until the async reopen succeeds"
        )

        await harness.service.pendingWindowReopenTask?.value

        XCTAssertNil(harness.recentlyClosedManager.mostRecentItem)
        XCTAssertTrue(harness.startupRestore.didConsumeRestoreOffer)
        XCTAssertEqual(harness.windowReopen.reopenedSessions.count, 1)
        XCTAssertEqual(
            harness.windowReopen.reopenedSnapshots.first?.id,
            sessionWindowId
        )
        XCTAssertNotEqual(sessionWindowId, item.id)
        XCTAssertNil(harness.service.pendingWindowReopenTask)
    }

    func testFailedWindowReopenKeepsHistoryItemAndRestoreOffer() async throws {
        let harness = makeHarness()
        harness.windowReopen.reopenResult = false
        harness.recentlyClosedManager.captureClosedWindow(
            sessionWindowId: UUID(),
            title: "Window",
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let item = try XCTUnwrap(harness.recentlyClosedManager.mostRecentItem)

        harness.service.reopen(item)
        await harness.service.pendingWindowReopenTask?.value

        XCTAssertEqual(harness.recentlyClosedManager.mostRecentItem?.id, item.id)
        XCTAssertFalse(harness.startupRestore.didConsumeRestoreOffer)
    }

    func testWindowItemInFlightIsNotReopenedTwice() async throws {
        let harness = makeHarness()
        harness.windowReopen.onReopen = {
            await Task.yield()
            await Task.yield()
        }
        harness.recentlyClosedManager.captureClosedWindow(
            sessionWindowId: UUID(),
            title: "Window",
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let item = try XCTUnwrap(harness.recentlyClosedManager.mostRecentItem)

        harness.service.reopen(item)
        harness.service.reopen(item)
        await harness.service.pendingWindowReopenTask?.value

        XCTAssertEqual(harness.windowReopen.reopenedSessions.count, 1)
    }

    func testDifferentWindowItemWaitsWhileAnotherReopenIsInFlight() async throws {
        let harness = makeHarness()
        harness.windowReopen.onReopen = {
            await Task.yield()
            await Task.yield()
        }
        harness.recentlyClosedManager.captureClosedWindow(
            sessionWindowId: UUID(),
            title: "First",
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        harness.recentlyClosedManager.captureClosedWindow(
            sessionWindowId: UUID(),
            title: "Second",
            session: makeSessionRecoveryWindowSession(currentTabId: UUID())
        )
        let firstItem = try XCTUnwrap(harness.recentlyClosedManager.items.first)
        let waitingItem = try XCTUnwrap(harness.recentlyClosedManager.items.last)

        harness.service.reopen(firstItem)
        harness.service.reopen(waitingItem)
        await harness.service.pendingWindowReopenTask?.value

        XCTAssertEqual(harness.windowReopen.reopenedSessions.count, 1)
        XCTAssertTrue(harness.recentlyClosedManager.items.contains { $0.id == waitingItem.id })
    }

    func testSessionRecoveryServicesDoNotRetainBrowserManager() async throws {
        var browserManager: BrowserManager? = BrowserManager()
        weak let releasedBrowserManager = browserManager
        var sessionRecovery: BrowserSessionRecoveryCommands? =
            try XCTUnwrap(browserManager).windowSessionBundle.sessionRecovery
        weak let releasedSessionRecovery = sessionRecovery

        browserManager = nil

        XCTAssertNil(
            releasedBrowserManager,
            "Session-recovery services must not keep BrowserManager alive"
        )
        XCTAssertNotNil(sessionRecovery)

        sessionRecovery = nil
        XCTAssertNil(releasedSessionRecovery)
    }

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager()
        let recentlyClosedManager = RecentlyClosedManager()
        let startupRestore = StartupSessionRestoreProviderFake()
        let windowReopen = WindowSessionReopenerFake()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.structuralCollectionMutationOwner.setTabs([], for: space.id)
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        let tabRestore = ClosedTabRestoreService(
            regularLifecycle: browserManager.regularTabLifecycleOwner,
            destinations: ClosedTabDestinationResolver(
                spaces: browserManager.spaceStateOwner,
                windows: browserManager.windowRegistry
            ),
            publication: ClosedTabRestorePublication(
                activeSelection: browserManager.activeSelectionOwner,
                browserSelection: browserManager.browserTabSelection
            )
        )
        let launcherRestore = ClosedShortcutLauncherRestoreTransaction(
            pins: browserManager.shortcutPinCollectionStateOwner,
            pinStore: browserManager.shortcutPinStoreOwner,
            persistence: browserManager.structuralPersistence,
            destinations: ClosedShortcutLauncherDestinationResolver(
                folders: browserManager.folderCollectionStateOwner,
                runtimeConnection: browserManager.runtimePortConnection,
                spaces: browserManager.spaceStateOwner,
                profiles: browserManager.profileManager
            )
        )
        let shortcutRestore = ClosedShortcutRestoreService(
            liveInstances: ClosedShortcutLiveRestoreTransaction(
                pins: browserManager.shortcutPinCollectionStateOwner,
                activation: browserManager.shortcutPresentationActivation,
                windows: ClosedShortcutWindowQuery(
                    windows: browserManager.windowRegistry
                ),
                selection: browserManager.browserTabSelection,
                launchers: launcherRestore
            ),
            launchers: launcherRestore
        )
        let service = RecentlyClosedItemReopenService(
            recentlyClosedItems: recentlyClosedManager,
            startupRestore: startupRestore,
            tabRestore: tabRestore,
            shortcutRestore: shortcutRestore,
            windowReopen: windowReopen
        )

        return Harness(
            browserManager: browserManager,
            recentlyClosedManager: recentlyClosedManager,
            startupRestore: startupRestore,
            windowReopen: windowReopen,
            space: space,
            service: service
        )
    }

    @MainActor
    private struct Harness {
        let browserManager: BrowserManager
        let recentlyClosedManager: RecentlyClosedManager
        let startupRestore: StartupSessionRestoreProviderFake
        let windowReopen: WindowSessionReopenerFake
        let space: Space
        let service: RecentlyClosedItemReopenService
    }
}
