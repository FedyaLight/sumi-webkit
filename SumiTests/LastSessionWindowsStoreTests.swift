import XCTest

@testable import Sumi

@MainActor
final class LastSessionWindowsStoreTests: XCTestCase {
    func testStorePersistsSnapshotsToUserDefaults() throws {
        let suiteName = "SumiTests.LastSessionWindowsStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = LastSessionWindowsStore(userDefaults: defaults)
        let snapshot = makeWindowSnapshot()

        store.updateSnapshots([snapshot])

        let reloaded = LastSessionWindowsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.snapshots, [snapshot])
        XCTAssertNil(reloaded.tabSnapshot)
        defaults.removePersistentDomain(forName: suiteName)
    }

    func testStorePersistsStartupArchiveWithTabSnapshot() throws {
        let suiteName = "SumiTests.LastSessionWindowsStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = LastSessionWindowsStore(userDefaults: defaults)
        let windowSnapshot = makeWindowSnapshot()
        let tabSnapshot = makeTabSnapshot()

        store.updateSnapshots([windowSnapshot], tabSnapshot: tabSnapshot)

        let reloaded = LastSessionWindowsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.snapshots, [windowSnapshot])
        XCTAssertEqual(reloaded.tabSnapshot?.spaces.map(\.id), tabSnapshot.spaces.map(\.id))
        XCTAssertEqual(reloaded.tabSnapshot?.tabs.map(\.id), tabSnapshot.tabs.map(\.id))
        XCTAssertEqual(reloaded.tabSnapshot?.state.currentSpaceID, tabSnapshot.state.currentSpaceID)
        defaults.removePersistentDomain(forName: suiteName)
    }

    private func makeWindowSnapshot() -> LastSessionWindowSnapshot {
        LastSessionWindowSnapshot(
            id: UUID(),
            session: WindowSessionSnapshot(
                currentTabId: nil,
                currentSpaceId: UUID(),
                currentProfileId: nil,
                activeShortcutPinId: nil,
                activeShortcutPinRole: nil,
                isShowingEmptyState: false,
                commandPaletteReason: nil,
                activeTabsBySpace: [],
                activeShortcutsBySpace: [],
                sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
                savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
                sidebarContentWidth: Double(BrowserWindowState.sidebarContentWidth(
                    for: BrowserWindowState.sidebarDefaultWidth
                )),
                isSidebarVisible: true,
                urlBarDraft: URLBarDraftState(text: "", navigateCurrentTab: false),
                splitSession: nil
            )
        )
    }

    private func makeTabSnapshot() -> TabSnapshotRepository.Snapshot {
        let spaceId = UUID()
        let tabId = UUID()
        return TabSnapshotRepository.Snapshot(
            spaces: [
                TabSnapshotRepository.SnapshotSpace(
                    id: spaceId,
                    name: "Restored",
                    icon: "globe",
                    index: 0,
                    gradientData: nil,
                    workspaceThemeData: nil,
                    profileId: nil
                )
            ],
            tabs: [
                TabSnapshotRepository.SnapshotTab(
                    id: tabId,
                    urlString: "https://example.com",
                    name: "Example",
                    index: 0,
                    spaceId: spaceId,
                    isPinned: false,
                    isSpacePinned: false,
                    profileId: nil,
                    folderId: nil,
                    iconAsset: nil,
                    currentURLString: "https://example.com",
                    canGoBack: false,
                    canGoForward: false
                )
            ],
            folders: [],
            state: TabSnapshotRepository.SnapshotState(
                currentTabID: tabId,
                currentSpaceID: spaceId
            )
        )
    }
}
