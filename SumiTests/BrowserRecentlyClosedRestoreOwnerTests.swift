import XCTest

@testable import Sumi

@MainActor
final class BrowserRecentlyClosedRestoreOwnerTests: XCTestCase {
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
                currentProfile: { nil },
                space: { _ in nil },
                selectTab: { _, _ in }
            )
        )

        XCTAssertTrue(owner.canOfferStartupLastSessionRestoreShortcut)
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
            floatingBarDraft: FloatingBarDraftState(text: "", navigateCurrentTab: false),
            splitSession: nil
        )
    }
}

private enum Event: Equatable {
    case mergeTabSnapshot
    case reopen
    case refresh(UUID?)
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
