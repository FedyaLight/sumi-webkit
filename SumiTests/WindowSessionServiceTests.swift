import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class WindowSessionServiceTests: XCTestCase {
    func testSetupWindowStatePreservesSeededThemeUntilInitialTabManagerLoadCompletes() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        XCTAssertFalse(tabManager.hasLoadedInitialData)

        let spaceId = UUID()
        let sessionKey = try seedWindowSession(currentSpaceId: spaceId)
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let initialTheme = makeVisibleTheme()
        let windowState = BrowserWindowState(initialWorkspaceTheme: initialTheme)
        let service = WindowSessionService(lastWindowSessionKey: sessionKey)
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)

        service.setupWindowState(windowState, delegate: delegate)

        XCTAssertEqual(windowState.currentSpaceId, spaceId)
        XCTAssertTrue(windowState.workspaceTheme.visuallyEquals(initialTheme))
        XCTAssertFalse(windowState.workspaceTheme.visuallyEquals(.default))
        XCTAssertTrue(delegate.committedThemes.isEmpty)
    }

    func testSetupWindowStateFallsBackToDefaultWhenLoadedSpaceIsMissing() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        tabManager.loadFromStore()
        XCTAssertTrue(tabManager.hasLoadedInitialData)
        tabManager.spaces = []
        tabManager.currentSpace = nil
        tabManager.currentTab = nil

        let spaceId = UUID()
        let sessionKey = try seedWindowSession(currentSpaceId: spaceId)
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let windowState = BrowserWindowState(initialWorkspaceTheme: makeVisibleTheme())
        let service = WindowSessionService(lastWindowSessionKey: sessionKey)
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)

        service.setupWindowState(windowState, delegate: delegate)

        XCTAssertEqual(windowState.currentSpaceId, spaceId)
        XCTAssertTrue(windowState.workspaceTheme.visuallyEquals(.default))
        XCTAssertEqual(delegate.committedThemes.count, 1)
        XCTAssertTrue(delegate.committedThemes[0].visuallyEquals(.default))
    }

    private func makeInMemoryTabManager(loadPersistedState: Bool) throws -> TabManager {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return TabManager(context: container.mainContext, loadPersistedState: loadPersistedState)
    }

    private func makeVisibleTheme() -> WorkspaceTheme {
        WorkspaceTheme(
            gradient: SpaceGradient(
                angle: 132,
                nodes: [
                    GradientNode(colorHex: "#FF3B30", location: 0.0),
                    GradientNode(colorHex: "#34C759", location: 1.0)
                ],
                grain: 0.2,
                opacity: 0.82
            )
        )
    }

    private func seedWindowSession(currentSpaceId: UUID) throws -> String {
        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        let snapshot = WindowSessionSnapshot(
            currentTabId: nil,
            currentSpaceId: currentSpaceId,
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
            selectedSidebarMenuSection: .history,
            urlBarDraft: URLBarDraftState(text: "", navigateCurrentTab: false),
            splitSession: nil
        )
        UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: sessionKey)
        return sessionKey
    }
}

@MainActor
private final class TestWindowSessionDelegate: WindowSessionServiceDelegate {
    let tabManager: TabManager
    let splitManager = SplitViewManager()
    let shellSelectionService = ShellSelectionService(splitTabsForWindow: { _ in (nil, nil) })
    var currentProfile: Profile?
    var windowRegistry: WindowRegistry?
    private let themeCoordinator = WorkspaceThemeCoordinator()
    private(set) var committedThemes: [WorkspaceTheme] = []

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        false
    }

    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme: Bool,
        rememberSelection: Bool,
        persistSelection: Bool
    ) {
        windowState.currentTabId = tab.id
        if updateSpaceFromTab {
            windowState.currentSpaceId = tab.spaceId
        }
    }

    func showEmptyState(in windowState: BrowserWindowState) {
        windowState.isShowingEmptyState = true
    }

    func sanitizeCommandPaletteState(in windowState: BrowserWindowState) {}

    func syncShortcutSelectionState(for windowState: BrowserWindowState) {}

    func commitWorkspaceTheme(_ theme: WorkspaceTheme, for windowState: BrowserWindowState) {
        committedThemes.append(theme)
        themeCoordinator.restore(theme, in: windowState)
    }

    func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return tabManager.spaces.first { $0.id == spaceId }
    }

    func syncBrowserManagerSidebarCachesFromWindow(_ windowState: BrowserWindowState) {}
}
