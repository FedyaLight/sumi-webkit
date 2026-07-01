import XCTest

@testable import Sumi

@MainActor
final class BrowserRecentlyClosedRestoreOwnerTests: XCTestCase {
    func testReopenClosedTabUsesSourceProfileSpaceInsteadOfGlobalFallback() throws {
        let harness = try makeRestoreHarness()
        let tabState = RecentlyClosedTabState(
            id: UUID(),
            title: "Closed",
            url: URL(string: "https://closed.example")!,
            sourceSpaceId: nil,
            currentURL: nil,
            canGoBack: true,
            canGoForward: false,
            profileId: try XCTUnwrap(harness.currentProfileSpace.profileId)
        )

        harness.owner.reopenRecentlyClosedItem(.tab(tabState))

        let restored = try XCTUnwrap(harness.tabManager.tabs(in: harness.currentProfileSpace).first)
        XCTAssertEqual(restored.url, tabState.url)
        XCTAssertEqual(restored.name, "Closed")
        XCTAssertTrue(restored.restoredCanGoBack)
        XCTAssertFalse(restored.restoredCanGoForward)
        XCTAssertTrue(harness.tabManager.tabs(in: harness.fallbackSpace).isEmpty)
        XCTAssertEqual(harness.tabManager.currentTab?.id, restored.id)
    }

    func testReopenClosedTabWithoutSourceOrWindowDoesNotUseGlobalFallback() throws {
        let harness = try makeRestoreHarness()
        let closedTab = Tab(
            url: URL(string: "https://closed.example")!,
            name: "Closed"
        )
        harness.recentlyClosedManager.captureClosedTab(
            closedTab,
            sourceSpaceId: nil,
            currentURL: nil,
            canGoBack: false,
            canGoForward: false
        )
        let item = try XCTUnwrap(harness.recentlyClosedManager.mostRecentItem)

        harness.owner.reopenRecentlyClosedItem(item)

        XCTAssertTrue(harness.tabManager.tabs(in: harness.currentProfileSpace).isEmpty)
        XCTAssertTrue(harness.tabManager.tabs(in: harness.fallbackSpace).isEmpty)
        XCTAssertNil(harness.tabManager.currentTab)
        XCTAssertEqual(harness.recentlyClosedManager.mostRecentItem?.id, item.id)
        XCTAssertFalse(harness.startupRestore.didConsumeRestoreOffer)
    }

    func testRestoreSpacePinnedShortcutLauncherUsesSourceSpaceInsteadOfGlobalFallback()
        throws {
        let harness = try makeRestoreHarness()
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: harness.currentProfileSpace.id,
            index: 0,
            launchURL: URL(string: "https://shortcut.example")!,
            title: "Shortcut"
        )
        let pinState = RecentlyClosedShortcutPinState(pin: pin)

        harness.owner.reopenRecentlyClosedItem(
            .shortcutLauncher(
                RecentlyClosedShortcutLauncherState(id: UUID(), pin: pinState)
            )
        )

        let restoredPin = try XCTUnwrap(harness.tabManager.shortcutPin(by: pinState.id))
        XCTAssertEqual(restoredPin.spaceId, harness.currentProfileSpace.id)
        XCTAssertEqual(
            harness.tabManager.spacePinnedPins(for: harness.currentProfileSpace.id).map(\.id),
            [pinState.id]
        )
        XCTAssertTrue(harness.tabManager.spacePinnedPins(for: harness.fallbackSpace.id).isEmpty)
    }

    func testRestoreSpacePinnedShortcutLauncherWithoutSourceOrWindowDoesNotUseGlobalFallback()
        throws {
        let harness = try makeRestoreHarness()
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            spaceId: nil,
            index: 0,
            launchURL: URL(string: "https://shortcut.example")!,
            title: "Shortcut"
        )
        let pinState = RecentlyClosedShortcutPinState(pin: pin)

        harness.owner.reopenRecentlyClosedItem(
            .shortcutLauncher(
                RecentlyClosedShortcutLauncherState(id: UUID(), pin: pinState)
            )
        )

        XCTAssertNil(harness.tabManager.shortcutPin(by: pinState.id))
        XCTAssertTrue(harness.tabManager.spacePinnedPins(for: harness.currentProfileSpace.id).isEmpty)
        XCTAssertTrue(harness.tabManager.spacePinnedPins(for: harness.fallbackSpace.id).isEmpty)
        XCTAssertFalse(harness.startupRestore.didConsumeRestoreOffer)
    }

    func testReopenAllWindowsFromLastSessionUsesStartupArchiveMergesTabSnapshotSkipsExistingSessionAndRefreshesStore() async throws {
        let store = try makeLastSessionWindowsStore()
        let browserManager = BrowserManager()
        let tabManager = browserManager.tabManager
        let existingSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeWindowSession(currentTabId: UUID())
        )
        let snapshotToRestore = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeWindowSession(currentTabId: UUID())
        )
        let startupTabSnapshot = TabSnapshotRepository.Snapshot(
            spaces: [],
            tabs: [],
            folders: [],
            state: TabSnapshotRepository.SnapshotState(currentTabID: nil, currentSpaceID: nil)
        )
        let startupRestore = FakeRecentlyClosedStartupRestoreProvider(
            canOfferRestoreShortcut: true,
            windowSnapshots: [existingSnapshot, snapshotToRestore],
            tabSnapshot: startupTabSnapshot
        )
        var events: [Event] = []
        var reopenedSessions: [WindowSessionSnapshot] = []
        var didMergeTabSnapshot = false

        let owner = BrowserRecentlyClosedRestoreOwner(
            dependencies: BrowserRecentlyClosedRestoreOwner.Dependencies(
                recentlyClosedManager: { RecentlyClosedManager() },
                startupRestore: startupRestore,
                lastSessionWindowsStore: { store },
                currentRegularWindowSnapshots: { excludedWindowId in
                    XCTAssertNil(excludedWindowId)
                    return [existingSnapshot]
                },
                refreshLastSessionWindowsStore: { excludedWindowId in
                    events.append(.refresh(excludedWindowId))
                },
                reopenWindow: { session in
                    events.append(.reopen)
                    reopenedSessions.append(session)
                },
                mergeSnapshotForLastSessionRestore: { _ in
                    events.append(.mergeTabSnapshot)
                    didMergeTabSnapshot = true
                },
                activeWindow: { nil },
                windowState: { _ in nil },
                tabManager: { tabManager },
                profileManager: { browserManager.profileManager },
                space: { _ in nil },
                selectTab: { _, _ in /* No-op. */ }
            )
        )

        XCTAssertTrue(owner.canOfferStartupSessionRestoreShortcut)
        XCTAssertTrue(owner.canRestoreAnyLastSession)

        owner.reopenAllWindowsFromLastSession()
        XCTAssertTrue(startupRestore.didConsumeRestoreOffer)

        await drainMainQueue()

        XCTAssertEqual(events, [.mergeTabSnapshot, .reopen, .refresh(nil)])
        XCTAssertTrue(didMergeTabSnapshot)
        XCTAssertEqual(reopenedSessions, [snapshotToRestore.session])
    }

    private func makeLastSessionWindowsStore() throws -> LastSessionWindowsStore {
        let suiteName = "BrowserRecentlyClosedRestoreOwnerTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return LastSessionWindowsStore(userDefaults: userDefaults)
    }

    private func makeRestoreHarness() throws -> RestoreHarness {
        let store = try makeLastSessionWindowsStore()
        let browserManager = BrowserManager()
        let recentlyClosedManager = RecentlyClosedManager()
        let startupRestore = FakeRecentlyClosedStartupRestoreProvider(
            canOfferRestoreShortcut: false,
            windowSnapshots: [],
            tabSnapshot: nil
        )
        let fallbackProfile = Profile(name: "Fallback")
        let currentProfile = Profile(name: "Current")
        let fallbackSpace = Space(name: "Fallback", profileId: fallbackProfile.id)
        let currentProfileSpace = Space(name: "Current", profileId: currentProfile.id)

        browserManager.profileManager.profiles = [fallbackProfile, currentProfile]
        browserManager.currentProfile = currentProfile
        browserManager.tabManager.spaces = [fallbackSpace, currentProfileSpace]
        browserManager.tabManager.setTabs([], for: fallbackSpace.id)
        browserManager.tabManager.setTabs([], for: currentProfileSpace.id)
        browserManager.tabManager.currentSpace = fallbackSpace

        let owner = BrowserRecentlyClosedRestoreOwner(
            dependencies: BrowserRecentlyClosedRestoreOwner.Dependencies(
                recentlyClosedManager: { recentlyClosedManager },
                startupRestore: startupRestore,
                lastSessionWindowsStore: { store },
                currentRegularWindowSnapshots: { _ in [] },
                refreshLastSessionWindowsStore: { _ in /* No-op. */ },
                reopenWindow: { _ in /* No-op. */ },
                mergeSnapshotForLastSessionRestore: { _ in /* No-op. */ },
                activeWindow: { nil },
                windowState: { _ in nil },
                tabManager: { browserManager.tabManager },
                profileManager: { browserManager.profileManager },
                space: { spaceId in
                    browserManager.tabManager.spaces.first { $0.id == spaceId }
                },
                selectTab: { _, _ in /* No-op. */ }
            )
        )

        return RestoreHarness(
            owner: owner,
            tabManager: browserManager.tabManager,
            recentlyClosedManager: recentlyClosedManager,
            startupRestore: startupRestore,
            fallbackSpace: fallbackSpace,
            currentProfileSpace: currentProfileSpace
        )
    }

    private func makeWindowSession(
        currentTabId: UUID? = nil
    ) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: currentTabId,
            currentSpaceId: UUID(),
            currentProfileId: nil,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: false,
            floatingBarReason: FloatingBarPresentationReason.none,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(
                BrowserWindowState.sidebarContentWidth(
                    for: BrowserWindowState.sidebarDefaultWidth
                )
            ),
            isSidebarVisible: true,
            floatingBarDraft: FloatingBarDraftState(text: "", navigateCurrentTab: false)
        )
    }
}

private enum Event: Equatable {
    case mergeTabSnapshot
    case reopen
    case refresh(UUID?)
}

@MainActor
private struct RestoreHarness {
    let owner: BrowserRecentlyClosedRestoreOwner
    let tabManager: TabManager
    let recentlyClosedManager: RecentlyClosedManager
    let startupRestore: FakeRecentlyClosedStartupRestoreProvider
    let fallbackSpace: Space
    let currentProfileSpace: Space
}

@MainActor
private final class FakeRecentlyClosedStartupRestoreProvider: BrowserStartupSessionRestoreProviding {
    var canOfferRestoreShortcut: Bool
    var windowSnapshots: [LastSessionWindowSnapshot]
    var tabSnapshot: TabSnapshotRepository.Snapshot?
    private(set) var didConsumeRestoreOffer = false

    init(
        canOfferRestoreShortcut: Bool,
        windowSnapshots: [LastSessionWindowSnapshot],
        tabSnapshot: TabSnapshotRepository.Snapshot?
    ) {
        self.canOfferRestoreShortcut = canOfferRestoreShortcut
        self.windowSnapshots = windowSnapshots
        self.tabSnapshot = tabSnapshot
    }

    func markRestoreOfferConsumed() {
        didConsumeRestoreOffer = true
        canOfferRestoreShortcut = false
    }
}

private func drainMainQueue() async {
    await Task.yield()
    await Task.yield()
}
