import XCTest

@testable import Sumi

@MainActor
final class WindowSessionArchiveRestoreTests: XCTestCase {
    func testApplyingExactSnapshotRefreshesLiveLastSessionArchive() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let profileID = UUID()
        let space = Space(name: "Restored", profileId: profileID)
        tabManager.spaceStateOwner.replaceSpaces([space])
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://restored.example",
            in: space,
            activate: false
        )
        let sourceWindow = BrowserWindowState()
        sourceWindow.currentProfileId = profileID
        sourceWindow.currentSpaceId = space.id
        sourceWindow.currentTabId = tab.id
        sourceWindow.sidebarWidth = 337
        sourceWindow.savedSidebarWidth = 337
        sourceWindow.sidebarContentWidth = BrowserWindowState.sidebarContentWidth(
            for: 337
        )

        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let registry = WindowRegistry()
        delegate.windowRegistry = registry
        let sessionKey = "SumiTests.windowSession.exactApply.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let service = delegate.makeRestoreService(
            lastWindowSessionKey: sessionKey
        )
        let targetWindow = BrowserWindowState()
        registry.register(targetWindow)
        let exactSnapshot = WindowSessionSnapshotFactory(
            splitManager: delegate.splitManager,
            glanceManager: delegate.glanceManager
        ).make(for: sourceWindow)

        service.applyWindowSessionSnapshot(exactSnapshot, to: targetWindow)

        let archived = try XCTUnwrap(
            delegate.lastSessionWindowsStore?.snapshots.first
        )
        XCTAssertEqual(archived.id, targetWindow.id)
        XCTAssertEqual(archived.session.currentProfileId, profileID)
        XCTAssertEqual(archived.session.currentSpaceId, space.id)
        XCTAssertEqual(archived.session.currentTabId, tab.id)
        XCTAssertEqual(archived.session.sidebarWidth, 337)
    }
}
