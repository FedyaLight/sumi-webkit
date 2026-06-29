import XCTest

@testable import Sumi

@MainActor
final class BrowserWindowHistorySessionOwnerTests: XCTestCase {
    func testHandleWindowWillCloseCapturesRestorableRegularWindowAndRefreshesSurvivingSessions() throws {
        let store = try makeLastSessionWindowsStore()
        let recentlyClosedManager = RecentlyClosedManager()
        let closedWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        let closedSession = makeWindowSession(currentTabId: UUID())
        let survivingSession = makeWindowSession(currentTabId: UUID())
        let sessions = [
            closedWindow.id: closedSession,
            survivingWindow.id: survivingSession,
        ]
        let startupRestore = FakeBrowserStartupSessionRestoreProvider()

        let owner = BrowserWindowHistorySessionOwner(
            dependencies: BrowserWindowHistorySessionOwner.Dependencies(
                windowState: { windowId in
                    [closedWindow.id: closedWindow, survivingWindow.id: survivingWindow][windowId]
                },
                allWindows: {
                    [closedWindow, survivingWindow]
                },
                makeWindowSessionSnapshot: { windowState in
                    sessions[windowState.id] ?? self.makeWindowSession()
                },
                windowDisplayTitle: { windowState in
                    windowState.id == closedWindow.id ? "Closed Window" : "Surviving Window"
                },
                recentlyClosedManager: {
                    recentlyClosedManager
                },
                lastSessionWindowsStore: {
                    store
                },
                startupRestore: startupRestore
            )
        )

        owner.handleWindowWillClose(closedWindow.id)

        guard case .window(let closedItem)? = recentlyClosedManager.items.first else {
            return XCTFail("Expected the closed regular window to be captured")
        }
        XCTAssertEqual(closedItem.title, "Closed Window")
        XCTAssertEqual(closedItem.session, closedSession)
        XCTAssertEqual(
            store.snapshots,
            [LastSessionWindowSnapshot(id: survivingWindow.id, session: survivingSession)]
        )
        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
    }

    func testRefreshLastSessionWindowsStoreMarksStartupOfferConsumedWhenMultipleWindowsRemain() throws {
        let store = try makeLastSessionWindowsStore()
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        let firstSession = makeWindowSession(currentTabId: UUID())
        let secondSession = makeWindowSession(currentTabId: UUID())
        let sessions = [
            firstWindow.id: firstSession,
            secondWindow.id: secondSession,
        ]
        let startupRestore = FakeBrowserStartupSessionRestoreProvider()

        let owner = BrowserWindowHistorySessionOwner(
            dependencies: BrowserWindowHistorySessionOwner.Dependencies(
                windowState: { _ in nil },
                allWindows: {
                    [firstWindow, secondWindow]
                },
                makeWindowSessionSnapshot: { windowState in
                    sessions[windowState.id] ?? self.makeWindowSession()
                },
                windowDisplayTitle: { _ in "Window" },
                recentlyClosedManager: {
                    RecentlyClosedManager()
                },
                lastSessionWindowsStore: {
                    store
                },
                startupRestore: startupRestore
            )
        )

        owner.refreshLastSessionWindowsStore(excludingWindowID: nil)

        XCTAssertEqual(
            store.snapshots,
            [
                LastSessionWindowSnapshot(id: firstWindow.id, session: firstSession),
                LastSessionWindowSnapshot(id: secondWindow.id, session: secondSession),
            ]
        )
        XCTAssertTrue(startupRestore.didConsumeRestoreOffer)
    }

    func testRefreshLastSessionWindowsStorePreservesStartupArchiveWhileManualRestoreIsOffered() throws {
        let store = try makeLastSessionWindowsStore()
        let currentWindow = BrowserWindowState()
        let currentSession = makeWindowSession(currentTabId: UUID())
        let startupSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: makeWindowSession(currentTabId: UUID())
        )
        let startupTabSnapshot = TabSnapshotRepository.Snapshot(
            spaces: [],
            tabs: [],
            folders: [],
            state: TabSnapshotRepository.SnapshotState(currentTabID: nil, currentSpaceID: nil)
        )
        let startupRestore = FakeBrowserStartupSessionRestoreProvider(
            canOfferRestoreShortcut: true,
            windowSnapshots: [startupSnapshot],
            tabSnapshot: startupTabSnapshot
        )

        let owner = BrowserWindowHistorySessionOwner(
            dependencies: BrowserWindowHistorySessionOwner.Dependencies(
                windowState: { _ in currentWindow },
                allWindows: {
                    [currentWindow]
                },
                makeWindowSessionSnapshot: { _ in
                    currentSession
                },
                windowDisplayTitle: { _ in "Current Window" },
                recentlyClosedManager: {
                    RecentlyClosedManager()
                },
                lastSessionWindowsStore: {
                    store
                },
                startupRestore: startupRestore
            )
        )

        owner.refreshLastSessionWindowsStore(excludingWindowID: nil)

        XCTAssertEqual(store.snapshots, [startupSnapshot])
        XCTAssertNotNil(store.tabSnapshot)
        XCTAssertFalse(startupRestore.didConsumeRestoreOffer)
    }

    private func makeLastSessionWindowsStore() throws -> LastSessionWindowsStore {
        let suiteName = "BrowserWindowHistorySessionOwnerTests-\(UUID().uuidString)"
        let userDefaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        userDefaults.removePersistentDomain(forName: suiteName)
        addTeardownBlock {
            userDefaults.removePersistentDomain(forName: suiteName)
        }
        return LastSessionWindowsStore(userDefaults: userDefaults)
    }

    private func makeWindowSession(
        currentTabId: UUID? = nil,
        splitSession: LegacySplitSessionSnapshot? = nil,
        isShowingEmptyState: Bool = false
    ) -> WindowSessionSnapshot {
        WindowSessionSnapshot(
            currentTabId: currentTabId,
            currentSpaceId: UUID(),
            currentProfileId: nil,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: isShowingEmptyState,
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
            splitSession: splitSession
        )
    }
}

@MainActor
private final class FakeBrowserStartupSessionRestoreProvider: BrowserStartupSessionRestoreProviding {
    var canOfferRestoreShortcut: Bool
    var windowSnapshots: [LastSessionWindowSnapshot]
    var tabSnapshot: TabSnapshotRepository.Snapshot?
    private(set) var didConsumeRestoreOffer = false

    init(
        canOfferRestoreShortcut: Bool = false,
        windowSnapshots: [LastSessionWindowSnapshot] = [],
        tabSnapshot: TabSnapshotRepository.Snapshot? = nil
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
