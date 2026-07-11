import SwiftData
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class WindowSessionServiceTests: XCTestCase {
    func testBrowserManagerFlushesPendingWindowSessionWithoutWaitingForDebounce() throws {
        let sessionKey = "SumiTests.windowSession.flush.\(UUID().uuidString)"
        UserDefaults.standard.removeObject(forKey: sessionKey)
        defer {
            UserDefaults.standard.removeObject(forKey: sessionKey)
        }

        let browserManager = BrowserManager(
            windowSessionSnapshotStore: WindowSessionSnapshotStore(
                key: sessionKey
            )
        )
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        windowState.currentSpaceId = spaceId
        windowState.sidebarWidth = 312
        windowState.savedSidebarWidth = 312
        windowState.sidebarContentWidth = BrowserWindowState.sidebarContentWidth(for: 312)

        browserManager.windowSessionBundle.persistence.schedule(
            windowState,
            delayNanoseconds: 60_000_000_000
        )

        XCTAssertNil(UserDefaults.standard.data(forKey: sessionKey))

        browserManager.windowSessionBundle.persistence.flush()

        let data = try XCTUnwrap(UserDefaults.standard.data(forKey: sessionKey))
        let snapshot = try JSONDecoder().decode(WindowSessionSnapshot.self, from: data)
        XCTAssertEqual(snapshot.currentSpaceId, spaceId)
        XCTAssertEqual(snapshot.sidebarWidth, 312)
    }

    func testSetupWindowStatePreservesSeededThemeUntilInitialTabManagerLoadCompletes() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        XCTAssertFalse(tabManager.startupRestoreLifecycle.hasLoadedInitialData)

        let spaceId = UUID()
        let sessionKey = try seedWindowSession(currentSpaceId: spaceId)
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let initialTheme = makeVisibleTheme()
        let windowState = BrowserWindowState(
            initialWorkspaceTheme: initialTheme,
            awaitsInitialSessionResolution: true
        )
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertEqual(windowState.currentSpaceId, spaceId)
        XCTAssertTrue(windowState.isAwaitingInitialSessionResolution)
        XCTAssertTrue(windowState.workspaceTheme.visuallyEquals(initialTheme))
        XCTAssertFalse(windowState.workspaceTheme.visuallyEquals(.default))
        XCTAssertTrue(delegate.committedThemes.isEmpty)
    }

    func testSetupWindowStateWithoutStoredSessionUsesFirstCurrentProfileSpaceInsteadOfGlobalCurrentSpace() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let primaryProfile = Profile(name: "Primary")
        let primarySpace = Space(name: "Primary", profileId: primaryProfile.id)
        let secondarySpace = Space(name: "Secondary", profileId: primaryProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([primarySpace, secondarySpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(secondarySpace)

        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        delegate.currentProfile = primaryProfile
        let windowState = BrowserWindowState()

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertEqual(windowState.currentProfileId, primaryProfile.id)
        XCTAssertEqual(windowState.currentSpaceId, primarySpace.id)
    }

    func testSetupWindowStateWithoutStoredSessionSelectsResolvedSpaceTabInsteadOfGlobalCurrentTab() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let primaryProfile = Profile(name: "Primary")
        let windowSpace = Space(name: "Window", profileId: primaryProfile.id)
        let globalSpace = Space(name: "Global", profileId: primaryProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([windowSpace, globalSpace])

        let windowTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://window.example",
            in: windowSpace,
            activate: false
        )
        let globalTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://global.example",
            in: globalSpace,
            activate: true
        )
        tabManager.spaceStateOwner.replaceCurrentSpace(globalSpace)
        tabManager.selectionStateOwner.replaceCurrentTab(globalTab)

        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        delegate.currentProfile = primaryProfile
        let windowState = BrowserWindowState()

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertEqual(windowState.currentSpaceId, windowSpace.id)
        XCTAssertEqual(windowState.currentTabId, windowTab.id)
        XCTAssertEqual(tabManager.selectionStateOwner.currentTab?.id, globalTab.id)
    }

    func testHandleTabManagerDataLoadedRepairsStaleWindowSpaceFromWindowProfileInsteadOfGlobalCurrentSpace()
        throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let primaryProfile = Profile(name: "Primary")
        let secondaryProfile = Profile(name: "Secondary")
        let primarySpace = Space(name: "Primary", profileId: primaryProfile.id)
        let secondarySpace = Space(name: "Secondary", profileId: secondaryProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([primarySpace, secondarySpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(secondarySpace)

        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowState.currentSpaceId = UUID()
        windowState.currentProfileId = primaryProfile.id
        delegate.currentProfile = secondaryProfile
        delegate.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry?.allWindows ?? [])

        XCTAssertEqual(windowState.currentProfileId, primaryProfile.id)
        XCTAssertEqual(windowState.currentSpaceId, primarySpace.id)
    }

    func testHandleTabManagerDataLoadedDoesNotUseCurrentProfileWhenPersistedProfileIsStale()
        throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let staleProfileId = UUID()
        let fallbackProfile = Profile(name: "Fallback")
        let currentProfile = Profile(name: "Current")
        let fallbackSpace = Space(name: "Fallback", profileId: fallbackProfile.id)
        let currentProfileSpace = Space(name: "Current", profileId: currentProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([fallbackSpace, currentProfileSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(fallbackSpace)

        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowState.currentSpaceId = UUID()
        windowState.currentProfileId = staleProfileId
        delegate.currentProfile = currentProfile
        delegate.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry?.allWindows ?? [])

        XCTAssertNil(windowState.currentProfileId)
        XCTAssertNil(windowState.currentSpaceId)
        XCTAssertTrue(windowState.isShowingEmptyState)
    }

    func testHandleTabManagerDataLoadedRepairsStaleWindowSpaceFromCurrentTabSpace() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let windowProfile = Profile(name: "Window")
        let globalProfile = Profile(name: "Global")
        let windowSpace = Space(name: "Window", profileId: windowProfile.id)
        let globalSpace = Space(name: "Global", profileId: globalProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([globalSpace, windowSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(globalSpace)
        let windowTab = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://window.example",
            in: windowSpace,
            activate: false
        )

        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowState.currentSpaceId = UUID()
        windowState.currentTabId = windowTab.id
        delegate.currentProfile = globalProfile
        delegate.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry?.allWindows ?? [])

        XCTAssertEqual(windowState.currentProfileId, windowProfile.id)
        XCTAssertEqual(windowState.currentSpaceId, windowSpace.id)
        XCTAssertEqual(windowState.currentTabId, windowTab.id)
    }

    func testWindowSessionBootstrapClassifiesCorruptStoredSnapshot() throws {
        let suiteName = "WindowSessionCorruptSnapshotTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let sessionKey = "SumiTests.windowSession.corrupt.\(UUID().uuidString)"
        defaults.set(Data("not-json".utf8), forKey: sessionKey)

        let store = WindowSessionSnapshotStore(
            key: sessionKey,
            userDefaults: defaults
        )
        let result = store.loadResult()

        guard case .failed(let failure) = result else {
            return XCTFail("Expected failed decode, got \(result)")
        }
        XCTAssertEqual(failure.source, .userDefaultsKey(sessionKey))
        XCTAssertEqual(failure.reason, .decodeFailed)
        XCTAssertFalse(failure.message.isEmpty)
        XCTAssertNil(store.loadSnapshot())
    }

    func testBrowserManagerCurrentTabRequiresCommittedWindowSelection() {
        let browserManager = BrowserManager()
        let space = Space(id: UUID(), name: "Primary")
        browserManager.tabManager.spaceStateOwner.replaceSpaces([space])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(space)

        let fallbackTab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://first.example",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowState.currentSpaceId = space.id

        XCTAssertNil(browserManager.shellRuntime.windowTabs.currentTab(for: windowState))

        windowState.isAwaitingInitialSessionResolution = false

        XCTAssertNil(browserManager.shellRuntime.windowTabs.currentTab(for: windowState))
        XCTAssertEqual(
            browserManager.shellRuntime.windowSelection.preferredTabForSpace(
                space,
                in: windowState,
                tabStore: browserManager.tabManager.runtimeStore
            )?.id,
            fallbackTab.id
        )
    }

    func testSetupWindowStateRestoresEmptyStateDraftWithoutSynthesizingFloatingBarReason() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let spaceId = UUID()
        let sessionKey = try seedWindowSession(
            currentSpaceId: spaceId,
            isShowingEmptyState: true,
            floatingBarReason: nil,
            floatingBarDraft: FloatingBarDraftState(text: "restored draft", navigateCurrentTab: true)
        )
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertTrue(windowState.isShowingEmptyState)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .none)
        XCTAssertEqual(windowState.floatingBarDraftText, "restored draft")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)
    }

    func testSetupWindowStatePreservesExplicitEmptyStateFloatingBarReasons() throws {
        for reason in [FloatingBarPresentationReason.emptySpace, .keyboard] {
            let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
            let spaceId = UUID()
            let sessionKey = try seedWindowSession(
                currentSpaceId: spaceId,
                isShowingEmptyState: true,
                floatingBarReason: reason,
                floatingBarDraft: FloatingBarDraftState(text: "restored draft", navigateCurrentTab: true)
            )
            defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

            let delegate = TestWindowSessionDelegate(tabManager: tabManager)
            let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
            let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)

            service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

            XCTAssertTrue(windowState.isShowingEmptyState)
            XCTAssertEqual(windowState.floatingBarPresentationReason, reason)
            XCTAssertEqual(windowState.floatingBarDraftText, "restored draft")
            XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)
        }
    }

    func testApplyWindowSessionSnapshotRestoresPersistedWindowFields() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let profileId = UUID()
        let space = tabManager.spaceServices.catalog.createSpace(name: "Snapshot", profileId: profileId)
        let tab = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://snapshot.example", in: space, activate: true)
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
            floatingBarDraft: FloatingBarDraftState(text: "persisted draft", navigateCurrentTab: true)
        )
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowState = BrowserWindowState()
        windowState.isDownloadsPopoverPresented = true

        service.applyWindowSessionSnapshot(snapshot, to: windowState)

        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertEqual(windowState.currentSpaceId, space.id)
        XCTAssertEqual(windowState.currentProfileId, profileId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertFalse(windowState.isShowingEmptyState)
        XCTAssertEqual(windowState.floatingBarPresentationReason, .none)
        XCTAssertEqual(windowState.activeTabForSpace[space.id], tab.id)
        XCTAssertNil(windowState.selectedShortcutPinForSpace[space.id])
        XCTAssertEqual(windowState.sidebarWidth, 312)
        XCTAssertEqual(windowState.savedSidebarWidth, 340)
        XCTAssertEqual(windowState.sidebarContentWidth, BrowserWindowState.sidebarContentWidth(for: 312))
        XCTAssertFalse(windowState.isSidebarVisible)
        XCTAssertFalse(windowState.isDownloadsPopoverPresented)
        XCTAssertEqual(windowState.floatingBarDraftText, "persisted draft")
        XCTAssertTrue(windowState.floatingBarDraftNavigatesCurrentTab)
    }

    func testPreparedArchivedWindowBypassesConflictingGlobalSnapshot() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let globalProfileID = UUID()
        let archivedProfileID = UUID()
        let globalSpace = Space(name: "Global", profileId: globalProfileID)
        let archivedSpace = Space(
            name: "Archived",
            profileId: archivedProfileID
        )
        tabManager.spaceStateOwner.replaceSpaces([globalSpace, archivedSpace])
        let sessionKey = try seedWindowSession(
            currentSpaceId: globalSpace.id,
            isShowingEmptyState: true
        )
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(
            lastWindowSessionKey: sessionKey
        )
        var archivedSession = makeSessionRecoveryWindowSession(
            isShowingEmptyState: true
        )
        archivedSession.currentSpaceId = archivedSpace.id
        archivedSession.currentProfileId = archivedProfileID
        let archivedSnapshot = LastSessionWindowSnapshot(
            id: UUID(),
            session: archivedSession
        )
        let restoredWindow = BrowserWindowState()

        service.prepareArchivedWindow(
            archivedSnapshot,
            forRegistration: restoredWindow
        )

        XCTAssertEqual(
            restoredWindow.restoredSessionWindowId,
            archivedSnapshot.id
        )
        XCTAssertEqual(restoredWindow.currentSpaceId, archivedSpace.id)
        XCTAssertEqual(restoredWindow.currentProfileId, archivedProfileID)
        XCTAssertTrue(restoredWindow.isAwaitingInitialSessionResolution)

        service.restoreRegisteredWindow(
            restoredWindow,
            currentProfile: Profile(name: "Conflicting")
        )

        XCTAssertEqual(restoredWindow.currentSpaceId, archivedSpace.id)
        XCTAssertEqual(restoredWindow.currentProfileId, archivedProfileID)
        XCTAssertFalse(restoredWindow.isAwaitingInitialSessionResolution)

        let ordinaryWindow = BrowserWindowState(
            awaitsInitialSessionResolution: true
        )
        service.setupWindowState(ordinaryWindow, currentProfile: nil)
        XCTAssertEqual(ordinaryWindow.currentSpaceId, globalSpace.id)
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

        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        delegate.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertEqual(windowState.currentTabId, staleLiveTabId)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .essential)
        XCTAssertTrue(windowState.isAwaitingInitialSessionResolution)

        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.structuralCollectionMutationOwner.setPinnedTabs([pin], for: profileId)
        tabManager.startupRestoreLifecycle.markLoadFinished()

        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry?.allWindows ?? [])

        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id))
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

        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        delegate.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertEqual(windowState.selectedShortcutPinForSpace[space.id], pin.id)
        XCTAssertTrue(windowState.isAwaitingInitialSessionResolution)

        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        tabManager.startupRestoreLifecycle.markLoadFinished()

        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry?.allWindows ?? [])

        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id))
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
        let space = tabManager.spaceServices.catalog.createSpace(name: "Split", profileId: UUID())
        let first = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://one.example", in: space, activate: true)
        let second = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://two.example", in: space, activate: false)
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(first.id), .regularTab(second.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        XCTAssertTrue(
            tabManager.splitGroupMutations.insert(group, persist: false)
        )

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
            splitSelection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(second.id)
            )
        )
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: "SumiTests.windowSession.\(UUID().uuidString)")
        let windowState = BrowserWindowState()

        service.applyWindowSessionSnapshot(snapshot, to: windowState)

        XCTAssertEqual(delegate.focusedSplitGroupIds, [group.id])
        XCTAssertEqual(windowState.currentTabId, second.id)
        XCTAssertNil(windowState.pendingSessionSplitSelection)
    }

    func testLegacySplitSessionSnapshotMigratesAfterTabLoad() throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        let space = tabManager.spaceServices.catalog.createSpace(name: "Legacy Split", profileId: UUID())
        let left = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://left.example", in: space, activate: true)
        let right = tabManager.regularTabLifecycleOwner.createNewTab(url: "https://right.example", in: space, activate: false)
        let sessionKey = try seedLegacySplitWindowSession(
            currentSpaceId: space.id,
            currentTabId: left.id,
            leftTabId: left.id,
            rightTabId: right.id,
            activeSideRawValue: "right",
            orientation: "vertical"
        )
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        delegate.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertEqual(windowState.currentTabId, left.id)
        XCTAssertNotNil(windowState.pendingSessionSplitSelection)
        XCTAssertNotNil(windowState.pendingSessionLegacySplitGroup)
        XCTAssertNil(
            tabManager.splitGroupStore.group(containing: .regularTab(left.id))
        )

        tabManager.startupRestoreLifecycle.markLoadFinished()
        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry?.allWindows ?? [])

        let group = try XCTUnwrap(
            tabManager.splitGroupStore.group(containing: .regularTab(left.id))
        )
        XCTAssertEqual(
            Set(group.memberIDs),
            Set([.regularTab(left.id), .regularTab(right.id)])
        )
        XCTAssertEqual(group.layoutKind, .horizontal)
        XCTAssertEqual(group.container, .regularTabs(spaceId: space.id))
        XCTAssertEqual(delegate.focusedSplitGroupIds, [group.id])
        XCTAssertEqual(windowState.currentTabId, right.id)
        XCTAssertEqual(
            windowState.splitSelection,
            WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(right.id)
            )
        )
        XCTAssertNil(windowState.pendingSessionSplitSelection)
        XCTAssertNil(windowState.pendingSessionLegacySplitGroup)
    }

    func testSetupWindowStateFallsBackToDefaultWhenLoadedSpaceIsMissing() async throws {
        let tabManager = try makeInMemoryTabManager(loadPersistedState: false)
        await tabManager.storeRestore.loadFromStoreAwaitingResult()
        XCTAssertTrue(tabManager.startupRestoreLifecycle.hasLoadedInitialData)
        tabManager.spaceStateOwner.replaceSpaces([])
        tabManager.spaceStateOwner.replaceCurrentSpace(nil)
        tabManager.selectionStateOwner.replaceCurrentTab(nil)

        let spaceId = UUID()
        let sessionKey = try seedWindowSession(currentSpaceId: spaceId)
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let windowState = BrowserWindowState(initialWorkspaceTheme: makeVisibleTheme())
        let delegate = TestWindowSessionDelegate(tabManager: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertEqual(windowState.currentSpaceId, spaceId)
        XCTAssertTrue(windowState.workspaceTheme.visuallyEquals(.default))
        XCTAssertEqual(delegate.committedThemes.count, 1)
        XCTAssertTrue(delegate.committedThemes[0].visuallyEquals(.default))
    }

    func testValidateWindowStatesRepairsStaleSpaceFromWindowProfileInsteadOfGlobalFallback() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer { UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey) }

        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let globalProfile = Profile(name: "Global")
        let windowProfile = Profile(name: "Window")
        let globalSpace = Space(name: "Global", profileId: globalProfile.id)
        let windowSpace = Space(name: "Window", profileId: windowProfile.id)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = UUID()
        windowState.currentProfileId = windowProfile.id
        windowState.isShowingEmptyState = true
        windowState.tabManager = browserManager.tabManager

        browserManager.currentProfile = globalProfile
        browserManager.profileManager.profiles = [globalProfile, windowProfile]
        browserManager.tabManager.spaceStateOwner.replaceSpaces([globalSpace, windowSpace])
        browserManager.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        browserManager.windowStateReconciler.validateWindowStates()

        XCTAssertEqual(windowState.currentSpaceId, windowSpace.id)
        XCTAssertEqual(windowState.currentProfileId, windowProfile.id)
    }

    func testValidateWindowStatesRepairsStaleSpaceFromCurrentTabSpace() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer { UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey) }

        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let globalProfile = Profile(name: "Global")
        let windowProfile = Profile(name: "Window")
        let globalSpace = Space(name: "Global", profileId: globalProfile.id)
        let windowSpace = Space(name: "Window", profileId: windowProfile.id)
        browserManager.currentProfile = globalProfile
        browserManager.profileManager.profiles = [globalProfile, windowProfile]
        browserManager.tabManager.spaceStateOwner.replaceSpaces([globalSpace, windowSpace])
        let windowTab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://window.example",
            in: windowSpace,
            activate: false
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = UUID()
        windowState.currentTabId = windowTab.id
        windowState.tabManager = browserManager.tabManager

        browserManager.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        browserManager.windowStateReconciler.validateWindowStates()

        XCTAssertEqual(windowState.currentSpaceId, windowSpace.id)
        XCTAssertEqual(windowState.currentProfileId, windowProfile.id)
        XCTAssertEqual(windowState.currentTabId, windowTab.id)
    }

    func testValidateWindowStatesDoesNotUseCurrentProfileOrFirstSpaceWithoutWindowContext() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer { UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey) }

        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let globalProfile = Profile(name: "Global")
        let otherProfile = Profile(name: "Other")
        let globalSpace = Space(name: "Global", profileId: globalProfile.id)
        let otherSpace = Space(name: "Other", profileId: otherProfile.id)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = UUID()
        windowState.isShowingEmptyState = false
        windowState.tabManager = browserManager.tabManager

        browserManager.currentProfile = globalProfile
        browserManager.profileManager.profiles = [globalProfile, otherProfile]
        browserManager.tabManager.spaceStateOwner.replaceSpaces([globalSpace, otherSpace])
        browserManager.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        browserManager.windowStateReconciler.validateWindowStates()

        XCTAssertNil(windowState.currentSpaceId)
        XCTAssertNil(windowState.currentProfileId)
        XCTAssertTrue(windowState.isShowingEmptyState)
    }

    func testValidateWindowStatesDoesNotMutateUnresolvedInitialSession() {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let pendingSpaceId = UUID()
        let pendingProfileId = UUID()
        let pendingTabId = UUID()
        let windowState = BrowserWindowState(
            awaitsInitialSessionResolution: true
        )
        windowState.currentSpaceId = pendingSpaceId
        windowState.currentProfileId = pendingProfileId
        windowState.currentTabId = pendingTabId
        windowState.tabManager = browserManager.tabManager

        browserManager.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        browserManager.windowStateReconciler.validateWindowStates()

        XCTAssertEqual(windowState.currentSpaceId, pendingSpaceId)
        XCTAssertEqual(windowState.currentProfileId, pendingProfileId)
        XCTAssertEqual(windowState.currentTabId, pendingTabId)
        XCTAssertFalse(windowState.isShowingEmptyState)
    }

    func testValidateWindowStatesPreservesIncognitoContextAndSelection() {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let ephemeralProfileId = UUID()
        let ephemeralSpaceId = UUID()
        let ephemeralTab = Tab(
            url: URL(string: "https://private.example")!,
            name: "Private",
            spaceId: ephemeralSpaceId,
            loadsCachedFaviconOnInit: false
        )
        let windowState = BrowserWindowState()
        windowState.isIncognito = true
        windowState.currentProfileId = ephemeralProfileId
        windowState.currentSpaceId = ephemeralSpaceId
        windowState.ephemeralTabs = [ephemeralTab]
        windowState.currentTabId = ephemeralTab.id
        windowState.tabManager = browserManager.tabManager

        browserManager.windowRegistry = windowRegistry
        windowRegistry.register(windowState)

        browserManager.windowStateReconciler.validateWindowStates()

        XCTAssertEqual(windowState.currentProfileId, ephemeralProfileId)
        XCTAssertEqual(windowState.currentSpaceId, ephemeralSpaceId)
        XCTAssertEqual(windowState.currentTabId, ephemeralTab.id)
        XCTAssertFalse(windowState.isShowingEmptyState)
    }

    func testSyncWindowSpaceContextDoesNotAdoptCurrentProfileWithoutWindowSpace() {
        let browserManager = BrowserManager()
        let processProfile = Profile(name: "Process")
        let staleProfileId = UUID()
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = UUID()
        windowState.currentProfileId = staleProfileId
        browserManager.currentProfile = processProfile
        browserManager.tabManager.spaceStateOwner.replaceSpaces([])

        browserManager.windowStateReconciler.synchronizeSpaceContext(
            in: windowState
        )

        XCTAssertNil(windowState.currentProfileId)
    }

    func testSetActiveWindowStateDoesNotSeedCurrentProfile() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer { UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey) }

        let browserManager = BrowserManager()
        let processProfile = Profile(name: "Process")
        let windowState = BrowserWindowState()
        browserManager.currentProfile = processProfile

        browserManager.windowSessionBundle.activation.activate(windowState)

        XCTAssertNil(windowState.currentProfileId)
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
            floatingBarDraft: floatingBarDraft
        )
        UserDefaults.standard.set(try JSONEncoder().encode(snapshot), forKey: sessionKey)
        return sessionKey
    }

    private func seedLegacySplitWindowSession(
        currentSpaceId: UUID,
        currentTabId: UUID,
        leftTabId: UUID,
        rightTabId: UUID,
        activeSideRawValue: String,
        orientation: String
    ) throws -> String {
        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        let payload: [String: Any] = [
            "currentTabId": currentTabId.uuidString,
            "currentSpaceId": currentSpaceId.uuidString,
            "isShowingEmptyState": false,
            "activeTabsBySpace": [],
            "activeShortcutsBySpace": [],
            "sidebarWidth": Double(BrowserWindowState.sidebarDefaultWidth),
            "savedSidebarWidth": Double(BrowserWindowState.sidebarDefaultWidth),
            "sidebarContentWidth": Double(BrowserWindowState.sidebarContentWidth(
                for: BrowserWindowState.sidebarDefaultWidth
            )),
            "isSidebarVisible": true,
            "floatingBarDraft": [
                "text": "",
                "navigateCurrentTab": false,
            ],
            "splitSession": [
                "leftTabId": leftTabId.uuidString,
                "rightTabId": rightTabId.uuidString,
                "dividerFraction": 0.5,
                "activeSideRawValue": activeSideRawValue,
                "orientation": orientation,
            ],
        ]
        let data = try JSONSerialization.data(withJSONObject: payload)
        UserDefaults.standard.set(data, forKey: sessionKey)
        return sessionKey
    }
}

@MainActor
final class TestWindowSessionDelegate:
    WindowSessionSelectionApplying,
    WindowSessionFloatingBarSanitizing,
    WindowSessionThemeCommitting,
    WindowSessionSplitFocusing {
    let tabManager: TabManager
    let glanceManager = GlanceManager()
    let shellSelectionService = ShellSelectionService(splitTabsForWindow: { _ in [] })
    var currentProfile: Profile?
    var windowRegistry: WindowRegistry?
    private(set) var persistenceComposition: WindowSessionPersistenceTestComposition?
    var lastSessionWindowsStore: LastSessionWindowsStore? {
        persistenceComposition?.lastSessionWindowsStore
    }
    private let themeCoordinator = WorkspaceThemeCoordinator()
    private(set) var committedThemes: [WorkspaceTheme] = []
    private(set) var focusedSplitGroupIds: [UUID] = []

    init(tabManager: TabManager) {
        self.tabManager = tabManager
    }

    func makeRestoreService(
        lastWindowSessionKey: String
    ) -> WindowSessionRestoreService {
        let store = WindowSessionSnapshotStore(key: lastWindowSessionKey)
        let scheduler = WindowSessionPersistenceScheduler()
        let snapshotFactory = WindowSessionSnapshotFactory(
            glanceManager: glanceManager
        )
        let persistenceComposition = WindowSessionPersistenceTestComposition(
            snapshotStore: store,
            scheduler: scheduler,
            snapshotFactory: snapshotFactory,
            openWindows: { [weak self] in
                self?.windowRegistry?.allWindows ?? []
            }
        )
        self.persistenceComposition = persistenceComposition
        return WindowSessionRestoreService(
            snapshotStore: store,
            persistence: persistenceComposition.coordinator,
            tabManager: tabManager,
            glanceManager: glanceManager,
            selectionService: shellSelectionService,
            selection: self,
            floatingBarSanitizer: self,
            themeCommitter: self,
            splitFocus: self
        )
    }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        windowState.currentTabId.map { tabManager.tabCollectionMembershipOwner.tab(for: $0) != nil } ?? false
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

    func showEmptyState(
        in windowState: BrowserWindowState,
        presentNewTabFloatingBar _: Bool
    ) {
        windowState.isShowingEmptyState = true
    }

    func sanitize(in _: BrowserWindowState) { /* no-op */ }

    func syncShortcutSelectionState(for _: BrowserWindowState) { /* no-op */ }

    func commitWorkspaceTheme(_ theme: WorkspaceTheme, for windowState: BrowserWindowState) {
        committedThemes.append(theme)
        themeCoordinator.restore(theme, in: windowState)
    }

    func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return tabManager.spaceStateOwner.spaces.first { $0.id == spaceId }
    }

    func focusSplitGroup(
        _ group: SplitGroup,
        preferredMemberID: SplitMemberID?,
        in windowState: BrowserWindowState
    ) {
        focusedSplitGroupIds.append(group.id)
        let selectedMemberID = preferredMemberID.flatMap {
            group.contains($0) ? $0 : nil
        } ?? group.memberIDs.first
        windowState.splitSelection = selectedMemberID.map {
            WindowSplitSelection(
                groupID: group.id,
                activeMemberID: $0
            )
        }
        let targetTabId = selectedMemberID.flatMap { memberID -> UUID? in
            guard case .regularTab(let tabID) = memberID else { return nil }
            return tabID
        }
        if let tab = targetTabId.flatMap({ tabManager.tabCollectionMembershipOwner.tab(for: $0) }) {
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
