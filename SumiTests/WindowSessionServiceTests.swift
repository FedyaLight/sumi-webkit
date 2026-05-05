import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class WindowSessionServiceTests: XCTestCase {
    func testBrowserManagerFlushesPendingWindowSessionWithoutWaitingForDebounce() throws {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        }

        let browserManager = BrowserManager()
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        windowState.currentSpaceId = spaceId
        windowState.sidebarWidth = 312
        windowState.savedSidebarWidth = 312
        windowState.sidebarContentWidth = BrowserWindowState.sidebarContentWidth(for: 312)

        browserManager.schedulePersistWindowSession(
            for: windowState,
            delayNanoseconds: 60_000_000_000
        )

        XCTAssertNil(UserDefaults.standard.data(forKey: BrowserManager.lastWindowSessionKey))

        browserManager.flushPendingWindowSessionPersistence()

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: BrowserManager.lastWindowSessionKey))
        let snapshot = try JSONDecoder().decode(WindowSessionSnapshot.self, from: data)
        XCTAssertEqual(snapshot.currentSpaceId, spaceId)
        XCTAssertEqual(snapshot.sidebarWidth, 312)
    }

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

    func testActiveEssentialShortcutSurvivesPreloadSetupAndMaterializesAfterTabLoad() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let space = Space(id: UUID(), name: "Primary")
        let profileId = UUID()
        let pin = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profileId,
            spaceId: nil,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential",
            iconAsset: nil
        )
        let staleLiveTabId = UUID()
        let sessionKey = try seedWindowSession(
            currentSpaceId: space.id,
            currentTabId: staleLiveTabId,
            activeShortcutPinId: pin.id,
            activeShortcutPinRole: .essential
        )
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let service = WindowSessionService(lastWindowSessionKey: sessionKey)
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState()
        delegate.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        service.setupWindowState(windowState, delegate: delegate)

        XCTAssertEqual(windowState.currentTabId, staleLiveTabId)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .essential)

        tabManager.spaces = [space]
        tabManager.currentSpace = space
        tabManager.setPinnedTabs([pin], for: profileId)
        tabManager.markInitialDataLoadFinished()

        service.handleTabManagerDataLoaded(delegate: delegate)

        let liveTab = try XCTUnwrap(tabManager.shortcutLiveTab(for: pin.id, in: windowState.id))
        XCTAssertEqual(windowState.currentTabId, liveTab.id)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .essential)
        XCTAssertFalse(windowState.isShowingEmptyState)
    }

    func testRememberedSpacePinnedShortcutSurvivesPreloadSetupAndMaterializesAfterTabLoad() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let space = Space(id: UUID(), name: "Primary")
        let pin = ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            profileId: nil,
            spaceId: space.id,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://space.example")!,
            title: "Space Pin",
            iconAsset: nil
        )
        let sessionKey = try seedWindowSession(
            currentSpaceId: space.id,
            activeShortcutsBySpace: [
                SpaceShortcutSelectionSnapshot(spaceId: space.id, shortcutPinId: pin.id)
            ]
        )
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let service = WindowSessionService(lastWindowSessionKey: sessionKey)
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState()
        delegate.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        service.setupWindowState(windowState, delegate: delegate)

        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertEqual(windowState.selectedShortcutPinForSpace[space.id], pin.id)

        tabManager.spaces = [space]
        tabManager.currentSpace = space
        tabManager.setSpacePinnedShortcuts([pin], for: space.id)
        tabManager.markInitialDataLoadFinished()

        service.handleTabManagerDataLoaded(delegate: delegate)

        let liveTab = try XCTUnwrap(tabManager.shortcutLiveTab(for: pin.id, in: windowState.id))
        XCTAssertEqual(windowState.currentTabId, liveTab.id)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .spacePinned)
        XCTAssertEqual(windowState.currentSpaceId, space.id)
        XCTAssertEqual(windowState.selectedShortcutPinForSpace[space.id], pin.id)
        XCTAssertFalse(windowState.isShowingEmptyState)
    }

    func testSetupWindowStateFallsBackToDefaultWhenLoadedSpaceIsMissing() async throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        await tabManager.loadFromStoreAwaitingResult()
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

    private func seedWindowSession(
        currentSpaceId: UUID,
        currentTabId: UUID? = nil,
        activeShortcutPinId: UUID? = nil,
        activeShortcutPinRole: ShortcutPinRole? = nil,
        activeShortcutsBySpace: [SpaceShortcutSelectionSnapshot] = []
    ) throws -> String {
        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        let snapshot = WindowSessionSnapshot(
            currentTabId: currentTabId,
            currentSpaceId: currentSpaceId,
            currentProfileId: nil,
            activeShortcutPinId: activeShortcutPinId,
            activeShortcutPinRole: activeShortcutPinRole,
            isShowingEmptyState: false,
            commandPaletteReason: nil,
            activeTabsBySpace: [],
            activeShortcutsBySpace: activeShortcutsBySpace,
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(BrowserWindowState.sidebarContentWidth(
                for: BrowserWindowState.sidebarDefaultWidth
            )),
            isSidebarVisible: true,
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
