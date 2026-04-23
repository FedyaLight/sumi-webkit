import XCTest

@testable import Sumi

@MainActor
final class LastSessionWindowsStoreTests: XCTestCase {
    func testStorePersistsSnapshotsToUserDefaults() throws {
        let suiteName = "SumiTests.LastSessionWindowsStore.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = LastSessionWindowsStore(userDefaults: defaults)
        let snapshot = LastSessionWindowSnapshot(
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
                isSidebarMenuVisible: false,
                selectedSidebarMenuSection: .downloads,
                urlBarDraft: URLBarDraftState(text: "", navigateCurrentTab: false),
                splitSession: nil
            )
        )

        store.updateSnapshots([snapshot])

        let reloaded = LastSessionWindowsStore(userDefaults: defaults)
        XCTAssertEqual(reloaded.snapshots, [snapshot])
        defaults.removePersistentDomain(forName: suiteName)
    }
}
