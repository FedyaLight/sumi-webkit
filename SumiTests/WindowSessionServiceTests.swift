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
        let windowState = BrowserWindowState(
            initialWorkspaceTheme: initialTheme,
            awaitsInitialSessionResolution: true
        )
        let service = WindowSessionService(lastWindowSessionKey: sessionKey)
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)

        service.setupWindowState(windowState, runtime: delegate.runtime)

        XCTAssertEqual(windowState.currentSpaceId, spaceId)
        XCTAssertTrue(windowState.isAwaitingInitialSessionResolution)
        XCTAssertTrue(windowState.workspaceTheme.visuallyEquals(initialTheme))
        XCTAssertFalse(windowState.workspaceTheme.visuallyEquals(.default))
        XCTAssertTrue(delegate.committedThemes.isEmpty)
    }

    func testWindowSessionBootstrapClassifiesCorruptStoredSnapshot() throws {
        let suiteName = "WindowSessionCorruptSnapshotTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionKey = "SumiTests.windowSession.corrupt.\(UUID().uuidString)"
        defaults.set(Data("not-json".utf8), forKey: sessionKey)

        let result = WindowSessionBootstrapOverride.resolvedSnapshotResult(
            userDefaults: defaults,
            lastWindowSessionKey: sessionKey
        )

        guard case .failed(let failure) = result else {
            return XCTFail("Expected failed decode, got \(result)")
        }
        XCTAssertEqual(failure.source, .userDefaultsKey(sessionKey))
        XCTAssertEqual(failure.reason, .decodeFailed)
        XCTAssertFalse(failure.message.isEmpty)
        XCTAssertNil(
            WindowSessionBootstrapOverride.resolvedSnapshot(
                userDefaults: defaults,
                lastWindowSessionKey: sessionKey
            )
        )
    }

    func testBrowserManagerSuppressesGlobalCurrentTabFallbackDuringInitialSessionResolution() {
        let browserManager = BrowserManager()
        let space = Space(id: UUID(), name: "Primary")
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        let fallbackTab = browserManager.tabManager.createNewTab(
            url: "https://first.example",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowState.currentSpaceId = space.id

        XCTAssertNil(browserManager.currentTab(for: windowState))

        windowState.isAwaitingInitialSessionResolution = false

        XCTAssertEqual(browserManager.currentTab(for: windowState)?.id, fallbackTab.id)
    }

    func testSetupWindowStateRestoresEmptyStateFloatingBarDraft() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let spaceId = UUID()
        let sessionKey = try seedWindowSession(
            currentSpaceId: spaceId,
            isShowingEmptyState: true,
            floatingBarReason: nil,
            floatingBarDraft: FloatingBarDraftState(text: "restored draft", navigateCurrentTab: true)
        )
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let service = WindowSessionService(lastWindowSessionKey: sessionKey)
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)

        service.setupWindowState(windowState, runtime: delegate.runtime)

        XCTAssertTrue(windowState.isShowingEmptyState)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .emptySpace)
        XCTAssertEqual(windowState.floatingBarDraftText, "restored draft")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)
    }

    func testApplyWindowSessionSnapshotRestoresPersistedWindowFields() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let profileId = UUID()
        let space = tabManager.createSpace(name: "Snapshot", profileId: profileId)
        let tab = tabManager.createNewTab(url: "https://snapshot.example", in: space, activate: true)
        let shortcutPinId = UUID()
        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let snapshot = WindowSessionSnapshot(
            currentTabId: tab.id,
            currentSpaceId: space.id,
            currentProfileId: profileId,
            activeShortcutPinId: shortcutPinId,
            activeShortcutPinRole: .spacePinned,
            isShowingEmptyState: false,
            floatingBarReason: .keyboard,
            activeTabsBySpace: [
                SpaceTabSelectionSnapshot(spaceId: space.id, tabId: tab.id),
            ],
            activeShortcutsBySpace: [
                SpaceShortcutSelectionSnapshot(spaceId: space.id, shortcutPinId: shortcutPinId),
            ],
            sidebarWidth: 312,
            savedSidebarWidth: 340,
            sidebarContentWidth: 1,
            isSidebarVisible: false,
            floatingBarDraft: FloatingBarDraftState(text: "persisted draft", navigateCurrentTab: true),
            splitSession: nil
        )
        let service = WindowSessionService(lastWindowSessionKey: sessionKey)
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let windowState = BrowserWindowState()
        windowState.isDownloadsPopoverPresented = true

        service.applyWindowSessionSnapshot(snapshot, to: windowState, runtime: delegate.runtime)

        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertEqual(windowState.currentSpaceId, space.id)
        XCTAssertEqual(windowState.currentProfileId, profileId)
        XCTAssertEqual(windowState.currentShortcutPinId, shortcutPinId)
        XCTAssertEqual(windowState.currentShortcutPinRole, .spacePinned)
        XCTAssertFalse(windowState.isShowingEmptyState)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .none)
        XCTAssertEqual(windowState.activeTabForSpace[space.id], tab.id)
        XCTAssertEqual(windowState.selectedShortcutPinForSpace[space.id], shortcutPinId)
        XCTAssertEqual(windowState.sidebarWidth, 312)
        XCTAssertEqual(windowState.savedSidebarWidth, 340)
        XCTAssertEqual(windowState.sidebarContentWidth, BrowserWindowState.sidebarContentWidth(for: 312))
        XCTAssertFalse(windowState.isSidebarVisible)
        XCTAssertFalse(windowState.isDownloadsPopoverPresented)
        XCTAssertEqual(windowState.floatingBarDraftText, "persisted draft")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)
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
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        delegate.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        service.setupWindowState(windowState, runtime: delegate.runtime)

        XCTAssertEqual(windowState.currentTabId, staleLiveTabId)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .essential)
        XCTAssertTrue(windowState.isAwaitingInitialSessionResolution)

        tabManager.spaces = [space]
        tabManager.currentSpace = space
        tabManager.setPinnedTabs([pin], for: profileId)
        tabManager.markInitialDataLoadFinished()

        service.handleTabManagerDataLoaded(runtime: delegate.runtime)

        let liveTab = try XCTUnwrap(tabManager.shortcutLiveTab(for: pin.id, in: windowState.id))
        XCTAssertEqual(windowState.currentTabId, liveTab.id)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .essential)
        XCTAssertFalse(windowState.isShowingEmptyState)
        XCTAssertFalse(windowState.isAwaitingInitialSessionResolution)
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
                SpaceShortcutSelectionSnapshot(spaceId: space.id, shortcutPinId: pin.id),
            ]
        )
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let service = WindowSessionService(lastWindowSessionKey: sessionKey)
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        delegate.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        service.setupWindowState(windowState, runtime: delegate.runtime)

        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertEqual(windowState.selectedShortcutPinForSpace[space.id], pin.id)
        XCTAssertTrue(windowState.isAwaitingInitialSessionResolution)

        tabManager.spaces = [space]
        tabManager.currentSpace = space
        tabManager.setSpacePinnedShortcuts([pin], for: space.id)
        tabManager.markInitialDataLoadFinished()

        service.handleTabManagerDataLoaded(runtime: delegate.runtime)

        let liveTab = try XCTUnwrap(tabManager.shortcutLiveTab(for: pin.id, in: windowState.id))
        XCTAssertEqual(windowState.currentTabId, liveTab.id)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .spacePinned)
        XCTAssertEqual(windowState.currentSpaceId, space.id)
        XCTAssertEqual(windowState.selectedShortcutPinForSpace[space.id], pin.id)
        XCTAssertFalse(windowState.isShowingEmptyState)
        XCTAssertFalse(windowState.isAwaitingInitialSessionResolution)
    }

    func testActiveSplitGroupSnapshotRestoresGroupFocus() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let space = tabManager.createSpace(name: "Split", profileId: UUID())
        let first = tabManager.createNewTab(url: "https://one.example", in: space, activate: true)
        let second = tabManager.createNewTab(url: "https://two.example", in: space, activate: false)
        let group = try XCTUnwrap(
            SplitGroup.make(
                tabIds: [first.id, second.id],
                layoutKind: .vertical,
                activeTabId: second.id,
                host: .regular(spaceId: space.id)
            )
        )
        tabManager.upsertSplitGroup(group, schedulePersistence: false)

        let snapshot = WindowSessionSnapshot(
            currentTabId: nil,
            currentSpaceId: space.id,
            currentProfileId: nil,
            activeShortcutPinId: nil,
            activeShortcutPinRole: nil,
            isShowingEmptyState: false,
            floatingBarReason: nil,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(BrowserWindowState.sidebarContentWidth(
                for: BrowserWindowState.sidebarDefaultWidth
            )),
            isSidebarVisible: true,
            floatingBarDraft: FloatingBarDraftState(text: "", navigateCurrentTab: false),
            activeSplitGroupId: group.id,
            splitSession: nil
        )
        let service = WindowSessionService(lastWindowSessionKey: "SumiTests.windowSession.\(UUID().uuidString)")
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let windowState = BrowserWindowState()

        service.applyWindowSessionSnapshot(snapshot, to: windowState, runtime: delegate.runtime)

        XCTAssertEqual(delegate.focusedSplitGroupIds, [group.id])
        XCTAssertEqual(windowState.currentTabId, second.id)
        XCTAssertNil(windowState.pendingSessionSplitGroupId)
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

        service.setupWindowState(windowState, runtime: delegate.runtime)

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
            gradientTheme: WorkspaceGradientTheme(
                colors: [
                    WorkspaceThemeColor(
                        hex: "#FF3B30",
                        isPrimary: true,
                        position: .topLeft
                    ),
                    WorkspaceThemeColor(
                        hex: "#34C759",
                        position: .bottom
                    ),
                ],
                opacity: 0.82,
                texture: 0.2
            )
        )
    }

    private func seedWindowSession(
        currentSpaceId: UUID,
        currentTabId: UUID? = nil,
        activeShortcutPinId: UUID? = nil,
        activeShortcutPinRole: ShortcutPinRole? = nil,
        activeShortcutsBySpace: [SpaceShortcutSelectionSnapshot] = [],
        isShowingEmptyState: Bool = false,
        floatingBarReason: FloatingBarPresentationReason? = nil,
        floatingBarDraft: FloatingBarDraftState = FloatingBarDraftState(text: "", navigateCurrentTab: false)
    ) throws -> String {
        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        let snapshot = WindowSessionSnapshot(
            currentTabId: currentTabId,
            currentSpaceId: currentSpaceId,
            currentProfileId: nil,
            activeShortcutPinId: activeShortcutPinId,
            activeShortcutPinRole: activeShortcutPinRole,
            isShowingEmptyState: isShowingEmptyState,
            floatingBarReason: floatingBarReason,
            activeTabsBySpace: [],
            activeShortcutsBySpace: activeShortcutsBySpace,
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(BrowserWindowState.sidebarContentWidth(
                for: BrowserWindowState.sidebarDefaultWidth
            )),
            isSidebarVisible: true,
            floatingBarDraft: floatingBarDraft,
            splitSession: nil
        )
        UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: sessionKey)
        return sessionKey
    }
}

@MainActor
private final class TestWindowSessionDelegate {
    let tabManager: TabManager
    let splitManager = SplitViewManager()
    let glanceManager = GlanceManager()
    let shellSelectionService = ShellSelectionService(splitTabsForWindow: { _ in [] })
    var currentProfile: Profile?
    var windowRegistry: WindowRegistry?
    private let themeCoordinator = WorkspaceThemeCoordinator()
    private(set) var committedThemes: [WorkspaceTheme] = []
    private(set) var focusedSplitGroupIds: [UUID] = []

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    var runtime: WindowSessionRuntime {
        WindowSessionRuntime(
            currentProfile: { self.currentProfile },
            tabManager: tabManager,
            windowRegistry: { self.windowRegistry },
            splitManager: splitManager,
            glanceManager: glanceManager,
            shellSelectionService: shellSelectionService,
            hasValidCurrentSelection: { [self] windowState in
                hasValidCurrentSelection(in: windowState)
            },
            applyTabSelection: { [self] tab, windowState, updateSpaceFromTab, updateTheme, rememberSelection, persistSelection in
                applyTabSelection(
                    tab,
                    in: windowState,
                    updateSpaceFromTab: updateSpaceFromTab,
                    updateTheme: updateTheme,
                    rememberSelection: rememberSelection,
                    persistSelection: persistSelection
                )
            },
            showEmptyState: { [self] windowState in
                showEmptyState(in: windowState)
            },
            sanitizeFloatingBarState: { [self] windowState in
                sanitizeFloatingBarState(in: windowState)
            },
            syncShortcutSelectionState: { [self] windowState in
                syncShortcutSelectionState(for: windowState)
            },
            commitWorkspaceTheme: { [self] theme, windowState in
                commitWorkspaceTheme(theme, for: windowState)
            },
            space: { [self] spaceId in
                space(for: spaceId)
            },
            syncSidebarPresentationState: { [self] windowState in
                syncSidebarPresentationState(from: windowState)
            },
            focusSplitGroup: { [self] group, windowState in
                focusSplitGroup(group, in: windowState)
            }
        )
    }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        windowState.currentTabId.map { tabManager.tab(for: $0) != nil } ?? false
    }

    func applyTabSelection(
        _ tab: Tab,
        in windowState: BrowserWindowState,
        updateSpaceFromTab: Bool,
        updateTheme _: Bool,
        rememberSelection _: Bool,
        persistSelection _: Bool
    ) {
        windowState.currentTabId = tab.id
        if updateSpaceFromTab {
            windowState.currentSpaceId = tab.spaceId
        }
    }

    func showEmptyState(in windowState: BrowserWindowState) {
        windowState.isShowingEmptyState = true
    }

    func sanitizeFloatingBarState(in _: BrowserWindowState) { /* no-op */ }

    func syncShortcutSelectionState(for _: BrowserWindowState) { /* no-op */ }

    func commitWorkspaceTheme(_ theme: WorkspaceTheme, for windowState: BrowserWindowState) {
        committedThemes.append(theme)
        themeCoordinator.restore(theme, in: windowState)
    }

    func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return tabManager.spaces.first { $0.id == spaceId }
    }

    func syncSidebarPresentationState(from _: BrowserWindowState) { /* no-op */ }

    func focusSplitGroup(_ group: SplitGroup, in windowState: BrowserWindowState) {
        focusedSplitGroupIds.append(group.id)
        let targetTabId = group.activeTabId.flatMap { group.contains($0) ? $0 : nil }
            ?? group.tabIds.first
        if let tab = targetTabId.flatMap({ tabManager.tab(for: $0) }) {
            applyTabSelection(
                tab,
                in: windowState,
                updateSpaceFromTab: true,
                updateTheme: false,
                rememberSelection: false,
                persistSelection: false
            )
        }
    }
}
