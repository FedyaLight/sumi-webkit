import SumiDomain
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class WindowSessionServiceTests: XCTestCase {
    func testInitialDataLoadMaterializesPersistedSelectedRegularTab() throws {
        let snapshotStore = WindowSessionSnapshotStore(
            key: "SumiTests.windowSession.selected-load.\(UUID())"
        )
        let browser = BrowserManager(
            windowSessionSnapshotStore: snapshotStore
        )
        let profile = try XCTUnwrap(browser.currentProfile)
        let space = Space(name: "Restored", profileId: profile.id)
        browser.spaceStateOwner.replaceSpaces([space])
        browser.spaceStateOwner.replaceCurrentSpace(space)
        let tab = browser.regularTabLifecycleOwner.createNewTab(
            url: "https://example.com/restored-selected",
            in: space,
            activate: false
        )
        var snapshot = makeSessionRecoveryWindowSession(
            currentTabId: tab.id,
            isShowingEmptyState: false
        )
        snapshot.currentSpaceId = space.id
        snapshotStore.persist(snapshot)
        let windowState = BrowserWindowState(
            awaitsInitialSessionResolution: true
        )
        browser.windowRegistry.register(windowState)
        let restore = browser.windowSessionBundle.restoreService

        restore.setupWindowState(
            windowState,
            currentProfile: browser.currentProfile
        )
        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertTrue(tab.isUnloaded)

        browser.startupRestoreLifecycle.markLoadFinished()
        restore.handleTabManagerDataLoaded(windows: [windowState])

        XCTAssertFalse(tab.isUnloaded)
        let webView = try XCTUnwrap(
            browser.webViewSessions.webView(
                for: tab.id,
                in: windowState.id
            )
        )
        switch tab.mainFrameLoads.attemptStatus(on: webView) {
        case .waiting, .submitted:
            break
        case .unsubmitted:
            XCTFail("Restored selection did not transfer its first navigation")
        }
    }

    func testInitialWindowProjectsDurableChromeBeforeRegistration() throws {
        let browser = BrowserManager()
        var snapshot = makeSessionRecoveryWindowSession(
            isShowingEmptyState: true
        )
        snapshot.sidebarWidth = 344
        snapshot.savedSidebarWidth = 344
        snapshot.sidebarContentWidth = Double(
            BrowserWindowState.sidebarContentWidth(for: 344)
        )
        snapshot.isSidebarVisible = false
        let store = WindowSessionSnapshotStore(
            key: "SumiTests.windowSession.initial.\(UUID().uuidString)"
        )
        store.persist(snapshot)
        let delegate = TestWindowSessionDelegate(runtime: browser)
        let service = delegate.makeRestoreService(snapshotStore: store)
        let window = BrowserWindowState(
            awaitsInitialSessionResolution: true
        )

        XCTAssertTrue(
            service.prepareInitialWindow(
                window,
                currentProfile: browser.currentProfile
            )
        )

        XCTAssertEqual(window.sidebarWidth, 344)
        XCTAssertEqual(window.savedSidebarWidth, 344)
        XCTAssertFalse(window.isSidebarVisible)
        XCTAssertEqual(window.currentSpaceId, snapshot.currentSpaceId)
        XCTAssertTrue(window.restorationState.isAwaitingInitialResolution)
    }

    func testOverrideSnapshotWithBlockedAdmissionLeavesWindowUnseeded() throws {
        let tabManager = BrowserManager()
        let retiredProfile = try XCTUnwrap(tabManager.currentProfile)
        let fallback = try tabManager.profileManager.createProfile(
            name: "Fallback"
        )
        _ = try tabManager.profileReferenceAdmission.reserve(
            profile: retiredProfile,
            fallbackID: fallback.id
        )
        var overrideSnapshot = makeSessionRecoveryWindowSession(
            currentTabId: UUID(),
            isShowingEmptyState: false
        )
        overrideSnapshot.currentProfileId = retiredProfile.id
        let overrideURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("sumi-window-override-\(UUID()).json")
        let overrideData = try WindowSessionSnapshotCodec().encode(
            overrideSnapshot
        )
        try overrideData.write(to: overrideURL, options: .atomic)
        defer { try? FileManager.default.removeItem(at: overrideURL) }
        let snapshotStore = WindowSessionSnapshotStore(
            key: "SumiTests.windowSession.override.\(UUID())",
            environment: {
                [WindowSessionSnapshotStore.overridePathEnvironmentKey: overrideURL.path]
            }
        )
        let delegate = TestWindowSessionDelegate(runtime: tabManager)
        let service = delegate.makeRestoreService(
            snapshotStore: snapshotStore
        )
        let window = BrowserWindowState()

        service.setupWindowState(window, currentProfile: fallback)

        XCTAssertNil(window.currentProfileId)
        XCTAssertNil(window.currentTabId)
        XCTAssertTrue(window.isShowingEmptyState)
        XCTAssertEqual(try Data(contentsOf: overrideURL), overrideData)
    }

    func testBrowserManagerFlushesPendingWindowSessionWithoutWaitingForDebounce() throws {
        let sessionKey = "SumiTests.windowSession.flush.\(UUID().uuidString)"
        let snapshotStore = WindowSessionSnapshotStore(key: sessionKey)
        let browserManager = BrowserManager(
            windowSessionSnapshotStore: snapshotStore
        )
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        windowState.currentSpaceId = spaceId
        windowState.sidebarWidth = 312
        windowState.savedSidebarWidth = 312
        windowState.sidebarContentWidth = BrowserWindowState.sidebarContentWidth(for: 312)

        browserManager.windowSessionPersistenceCoordinator.schedule(
            windowState,
            delayNanoseconds: 60_000_000_000
        )

        XCTAssertNil(snapshotStore.loadSnapshot()?.snapshot)

        browserManager.windowSessionPersistenceCoordinator.flush()

        let snapshot = try XCTUnwrap(snapshotStore.loadSnapshot()?.snapshot)
        XCTAssertEqual(snapshot.currentSpaceId, spaceId)
        XCTAssertEqual(snapshot.sidebarWidth, 312)
    }

    func testSetupWindowStatePreservesSeededThemeUntilInitialTabManagerLoadCompletes() throws {
        let tabManager = BrowserManager()
        XCTAssertFalse(tabManager.startupRestoreLifecycle.hasLoadedInitialData)

        let spaceId = UUID()
        let sessionKey = try seedWindowSession(currentSpaceId: spaceId)
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let initialTheme = makeVisibleTheme()
        let windowState = BrowserWindowState(
            initialWorkspaceTheme: initialTheme,
            awaitsInitialSessionResolution: true
        )
        let delegate = TestWindowSessionDelegate(runtime: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertEqual(windowState.currentSpaceId, spaceId)
        XCTAssertTrue(windowState.restorationState.isAwaitingInitialResolution)
        XCTAssertTrue(windowState.workspaceTheme.visuallyEquals(initialTheme))
        XCTAssertFalse(windowState.workspaceTheme.visuallyEquals(.default))
        XCTAssertTrue(delegate.committedThemes.isEmpty)
    }

    func testSetupWindowStateWithoutStoredSessionUsesFirstCurrentProfileSpaceInsteadOfGlobalCurrentSpace() throws {
        let tabManager = BrowserManager()
        let primaryProfile = Profile(name: "Primary")
        let primarySpace = Space(name: "Primary", profileId: primaryProfile.id)
        let secondarySpace = Space(name: "Secondary", profileId: primaryProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([primarySpace, secondarySpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(secondarySpace)

        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let delegate = TestWindowSessionDelegate(runtime: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        delegate.currentProfile = primaryProfile
        let windowState = BrowserWindowState()

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertEqual(windowState.currentProfileId, primaryProfile.id)
        XCTAssertEqual(windowState.currentSpaceId, primarySpace.id)
    }

    func testSetupWindowStateWithoutStoredSessionSelectsResolvedSpaceTabInsteadOfGlobalCurrentTab() throws {
        let tabManager = BrowserManager()
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
        tabManager.activeSelectionOwner.setActiveTab(globalTab)

        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let delegate = TestWindowSessionDelegate(runtime: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        delegate.currentProfile = primaryProfile
        let windowState = BrowserWindowState()

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertEqual(windowState.currentSpaceId, windowSpace.id)
        XCTAssertEqual(windowState.currentTabId, windowTab.id)
        XCTAssertEqual(tabManager.tabStateStore.selection.currentTab?.id, globalTab.id)
    }

    func testHandleTabManagerDataLoadedRepairsStaleWindowSpaceFromWindowProfileInsteadOfGlobalCurrentSpace()
        throws {
        let tabManager = BrowserManager()
        let primaryProfile = Profile(name: "Primary")
        let secondaryProfile = Profile(name: "Secondary")
        let primarySpace = Space(name: "Primary", profileId: primaryProfile.id)
        let secondarySpace = Space(name: "Secondary", profileId: secondaryProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([primarySpace, secondarySpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(secondarySpace)

        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let windowRegistry = WindowRegistry()
        let delegate = TestWindowSessionDelegate(
            runtime: tabManager,
            windowRegistry: windowRegistry
        )
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowState.currentSpaceId = UUID()
        windowState.currentProfileId = primaryProfile.id
        delegate.currentProfile = secondaryProfile
        windowRegistry.register(windowState)

        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry.allWindows)

        XCTAssertEqual(windowState.currentProfileId, primaryProfile.id)
        XCTAssertEqual(windowState.currentSpaceId, primarySpace.id)
    }

    func testHandleTabManagerDataLoadedDoesNotUseCurrentProfileWhenPersistedProfileIsStale()
        throws {
        let tabManager = BrowserManager()
        let staleProfileId = UUID()
        let fallbackProfile = Profile(name: "Fallback")
        let currentProfile = Profile(name: "Current")
        let fallbackSpace = Space(name: "Fallback", profileId: fallbackProfile.id)
        let currentProfileSpace = Space(name: "Current", profileId: currentProfile.id)
        tabManager.spaceStateOwner.replaceSpaces([fallbackSpace, currentProfileSpace])
        tabManager.spaceStateOwner.replaceCurrentSpace(fallbackSpace)

        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }
        let windowRegistry = WindowRegistry()
        let delegate = TestWindowSessionDelegate(
            runtime: tabManager,
            windowRegistry: windowRegistry
        )
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowState.currentSpaceId = UUID()
        windowState.currentProfileId = staleProfileId
        delegate.currentProfile = currentProfile
        windowRegistry.register(windowState)

        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry.allWindows)

        XCTAssertNil(windowState.currentProfileId)
        XCTAssertNil(windowState.currentSpaceId)
        XCTAssertTrue(windowState.isShowingEmptyState)
    }

    func testHandleTabManagerDataLoadedRepairsStaleWindowSpaceFromCurrentTabSpace() throws {
        let tabManager = BrowserManager()
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
        let windowRegistry = WindowRegistry()
        let delegate = TestWindowSessionDelegate(
            runtime: tabManager,
            windowRegistry: windowRegistry
        )
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowState.currentSpaceId = UUID()
        windowState.currentTabId = windowTab.id
        delegate.currentProfile = globalProfile
        windowRegistry.register(windowState)

        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry.allWindows)

        XCTAssertEqual(windowState.currentProfileId, windowProfile.id)
        XCTAssertEqual(windowState.currentSpaceId, windowSpace.id)
        XCTAssertEqual(windowState.currentTabId, windowTab.id)
    }

    func testWindowSessionBootstrapClassifiesCorruptStoredSnapshot() throws {
        let database = try SumiDatabase.inMemory()
        let sessionKey = "SumiTests.windowSession.corrupt.\(UUID().uuidString)"
        try database.transaction {
            try $0.documents.save(Data("not-json".utf8), forKey: sessionKey)
        }

        let store = WindowSessionSnapshotStore(
            database: database,
            key: sessionKey
        )
        let result = store.loadResult()

        guard case .failed(let failure) = result else {
            return XCTFail("Expected failed decode, got \(result)")
        }
        XCTAssertEqual(failure.source, .databaseKey(sessionKey))
        XCTAssertEqual(failure.reason, .decodeFailed)
        XCTAssertFalse(failure.message.isEmpty)
        XCTAssertNil(store.loadSnapshot())
    }

    func testBrowserManagerCurrentTabRequiresCommittedWindowSelection() {
        let browserManager = BrowserManager()
        let space = Space(id: UUID(), name: "Primary")
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)

        let fallbackTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://first.example",
            in: space,
            activate: true
        )
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowState.currentSpaceId = space.id

        XCTAssertNil(browserManager.shellRuntime.windowTabs.currentTab(for: windowState))

        windowState.restorationState.isAwaitingInitialResolution = false

        XCTAssertNil(browserManager.shellRuntime.windowTabs.currentTab(for: windowState))
        XCTAssertEqual(
            browserManager.shellRuntime.windowSelection.preferredTabForSpace(
                space,
                in: windowState,
                tabStore: browserManager.runtimeStore
            )?.id,
            fallbackTab.id
        )
    }

    func testSetupWindowStateRestoresEmptyStateDraftWithoutSynthesizingCommandPaletteReason() throws {
        let tabManager = BrowserManager()
        let spaceId = UUID()
        let sessionKey = try seedWindowSession(
            currentSpaceId: spaceId,
            isShowingEmptyState: true,
            commandPaletteReason: nil,
            commandPaletteDraft: CommandPaletteDraftState(text: "restored draft", navigateCurrentTab: true)
        )
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let delegate = TestWindowSessionDelegate(runtime: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertTrue(windowState.isShowingEmptyState)
        XCTAssertEqual(windowState.commandPalettePresentationReason, .none)
        XCTAssertEqual(windowState.commandPaletteDraftText, "restored draft")
        XCTAssertTrue(windowState.commandPaletteDraftNavigatesCurrentTab)
    }

    func testSetupWindowStatePreservesExplicitEmptyStateCommandPaletteReasons() throws {
        for reason in [CommandPalettePresentationReason.emptySpace, .keyboard] {
            let tabManager = BrowserManager()
            let spaceId = UUID()
            let sessionKey = try seedWindowSession(
                currentSpaceId: spaceId,
                isShowingEmptyState: true,
                commandPaletteReason: reason,
                commandPaletteDraft: CommandPaletteDraftState(text: "restored draft", navigateCurrentTab: true)
            )
            defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let delegate = TestWindowSessionDelegate(runtime: tabManager)
            let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
            let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)

            service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

            XCTAssertTrue(windowState.isShowingEmptyState)
            XCTAssertEqual(windowState.commandPalettePresentationReason, reason)
            XCTAssertEqual(windowState.commandPaletteDraftText, "restored draft")
            XCTAssertTrue(windowState.commandPaletteDraftNavigatesCurrentTab)
        }
    }

    func testApplyWindowSessionSnapshotRestoresPersistedWindowFields() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = try createSpace(
            named: "Snapshot",
            profileID: profileId,
            in: tabManager
        )
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
            commandPaletteReason: .keyboard,
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
            commandPaletteDraft: CommandPaletteDraftState(text: "persisted draft", navigateCurrentTab: true)
        )
        let delegate = TestWindowSessionDelegate(runtime: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowState = BrowserWindowState()
        windowState.presentationState.isDownloadsPopoverPresented = true

        service.applyWindowSessionSnapshot(snapshot, to: windowState)

        XCTAssertEqual(windowState.currentTabId, tab.id)
        XCTAssertEqual(windowState.currentSpaceId, space.id)
        XCTAssertEqual(windowState.currentProfileId, profileId)
        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertNil(windowState.currentShortcutPinRole)
        XCTAssertFalse(windowState.isShowingEmptyState)
        XCTAssertEqual(windowState.commandPalettePresentationReason, .none)
        XCTAssertEqual(windowState.activeTabForSpace[space.id], tab.id)
        XCTAssertNil(windowState.selectedShortcutPinForSpace[space.id])
        XCTAssertEqual(windowState.sidebarWidth, 312)
        XCTAssertEqual(windowState.savedSidebarWidth, 340)
        XCTAssertEqual(windowState.sidebarContentWidth, BrowserWindowState.sidebarContentWidth(for: 312))
        XCTAssertFalse(windowState.isSidebarVisible)
        XCTAssertFalse(windowState.presentationState.isDownloadsPopoverPresented)
        XCTAssertEqual(windowState.commandPaletteDraftText, "persisted draft")
        XCTAssertTrue(windowState.commandPaletteDraftNavigatesCurrentTab)
    }

    func testPreparedArchivedWindowBypassesConflictingGlobalSnapshot() throws {
        let tabManager = BrowserManager()
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
        let delegate = TestWindowSessionDelegate(runtime: tabManager)
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
            restoredWindow.restorationState.restoredSessionWindowID,
            archivedSnapshot.id
        )
        XCTAssertEqual(restoredWindow.currentSpaceId, archivedSpace.id)
        XCTAssertEqual(restoredWindow.currentProfileId, archivedProfileID)
        XCTAssertTrue(restoredWindow.restorationState.isAwaitingInitialResolution)

        service.restoreRegisteredWindow(
            restoredWindow,
            currentProfile: Profile(name: "Conflicting")
        )

        XCTAssertEqual(restoredWindow.currentSpaceId, archivedSpace.id)
        XCTAssertEqual(restoredWindow.currentProfileId, archivedProfileID)
        XCTAssertFalse(restoredWindow.restorationState.isAwaitingInitialResolution)

        let ordinaryWindow = BrowserWindowState(
            awaitsInitialSessionResolution: true
        )
        service.setupWindowState(ordinaryWindow, currentProfile: nil)
        XCTAssertEqual(ordinaryWindow.currentSpaceId, globalSpace.id)
    }

    func testActiveFavoriteShortcutSurvivesPreloadSetupAndMaterializesAfterTabLoad() throws {
        let tabManager = BrowserManager()
        let profileId = UUID()
        let space = Space(
            id: UUID(),
            name: "Primary",
            profileId: profileId
        )
        let pin = ShortcutPin(
            id: UUID(),
            role: .favorite,
            profileId: profileId,
            spaceId: nil,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://favorite.example")!,
            title: "Favorite",
            iconAsset: nil
        )
        let staleLiveTabId = UUID()
        let sessionKey = try seedWindowSession(
            currentSpaceId: space.id,
            currentTabId: staleLiveTabId,
            activeShortcutPinId: pin.id,
            activeShortcutPinRole: .favorite
        )
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let windowRegistry = WindowRegistry()
        let delegate = TestWindowSessionDelegate(
            runtime: tabManager,
            windowRegistry: windowRegistry
        )
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowRegistry.register(windowState)

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertEqual(windowState.currentTabId, staleLiveTabId)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .favorite)
        XCTAssertTrue(windowState.restorationState.isAwaitingInitialResolution)

        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.structuralCollectionMutationOwner.setPinnedTabs([pin], for: profileId)
        tabManager.startupRestoreLifecycle.markLoadFinished()

        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry.allWindows)

        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id))
        XCTAssertEqual(windowState.currentTabId, liveTab.id)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .favorite)
        XCTAssertFalse(windowState.isShowingEmptyState)
        XCTAssertFalse(windowState.restorationState.isAwaitingInitialResolution)
    }

    func testRememberedSpacePinnedShortcutSurvivesPreloadSetupAndMaterializesAfterTabLoad() throws {
        let tabManager = BrowserManager()
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

        let windowRegistry = WindowRegistry()
        let delegate = TestWindowSessionDelegate(
            runtime: tabManager,
            windowRegistry: windowRegistry
        )
        let service = delegate.makeRestoreService(lastWindowSessionKey: sessionKey)
        let windowState = BrowserWindowState(awaitsInitialSessionResolution: true)
        windowRegistry.register(windowState)

        service.setupWindowState(windowState, currentProfile: delegate.currentProfile)

        XCTAssertNil(windowState.currentShortcutPinId)
        XCTAssertEqual(windowState.selectedShortcutPinForSpace[space.id], pin.id)
        XCTAssertTrue(windowState.restorationState.isAwaitingInitialResolution)

        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: space.id)
        tabManager.startupRestoreLifecycle.markLoadFinished()

        service.handleTabManagerDataLoaded(windows: delegate.windowRegistry.allWindows)

        let liveTab = try XCTUnwrap(tabManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: windowState.id))
        XCTAssertEqual(windowState.currentTabId, liveTab.id)
        XCTAssertEqual(windowState.currentShortcutPinId, pin.id)
        XCTAssertEqual(windowState.currentShortcutPinRole, .spacePinned)
        XCTAssertEqual(windowState.currentSpaceId, space.id)
        XCTAssertEqual(windowState.selectedShortcutPinForSpace[space.id], pin.id)
        XCTAssertFalse(windowState.isShowingEmptyState)
        XCTAssertFalse(windowState.restorationState.isAwaitingInitialResolution)
    }

    func testActiveSplitGroupSnapshotRestoresGroupFocus() throws {
        let tabManager = BrowserManager()
        let space = try createSpace(
            named: "Split",
            profileID: UUID(),
            in: tabManager
        )
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
            commandPaletteReason: nil,
            activeTabsBySpace: [],
            activeShortcutsBySpace: [],
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(BrowserWindowState.sidebarContentWidth(
                for: BrowserWindowState.sidebarDefaultWidth
            )),
            isSidebarVisible: true,
            commandPaletteDraft: CommandPaletteDraftState(text: "", navigateCurrentTab: false),
            splitSelection: WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(second.id)
            )
        )
        let delegate = TestWindowSessionDelegate(runtime: tabManager)
        let service = delegate.makeRestoreService(lastWindowSessionKey: "SumiTests.windowSession.\(UUID().uuidString)")
        let windowState = BrowserWindowState()

        service.applyWindowSessionSnapshot(snapshot, to: windowState)

        XCTAssertEqual(delegate.focusedSplitGroupIds, [group.id])
        XCTAssertEqual(windowState.currentTabId, second.id)
        XCTAssertNil(windowState.restorationState.pendingSplitSelection)
    }

    func testDeferredSplitSelectionRetriesOnlyAfterTabDataLoad() throws {
        let tabManager = BrowserManager()
        let space = try createSpace(
            named: "Deferred Split",
            profileID: UUID(),
            in: tabManager
        )
        let first = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://one.example",
            in: space,
            activate: true
        )
        let second = tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://two.example",
            in: space,
            activate: false
        )
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(first.id), .regularTab(second.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: space.id)
            )
        )
        let pendingSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(second.id)
        )
        let snapshot = WindowSessionSnapshot(
            currentTabId: first.id,
            currentSpaceId: space.id,
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
            commandPaletteDraft: CommandPaletteDraftState(
                text: "",
                navigateCurrentTab: false
            ),
            splitSelection: pendingSelection
        )
        let delegate = TestWindowSessionDelegate(runtime: tabManager)
        var didPublishGroup = false
        delegate.onSyncShortcutSelectionState = { _ in
            guard !didPublishGroup else { return }
            didPublishGroup = true
            XCTAssertTrue(
                tabManager.splitGroupMutations.insert(group, persist: false)
            )
        }
        let service = delegate.makeRestoreService(
            lastWindowSessionKey: "SumiTests.windowSession.\(UUID().uuidString)"
        )
        let windowState = BrowserWindowState()

        service.applyWindowSessionSnapshot(snapshot, to: windowState)

        XCTAssertTrue(didPublishGroup)
        XCTAssertEqual(delegate.focusedSplitGroupIds, [])
        XCTAssertEqual(
            windowState.restorationState.pendingSplitSelection,
            PendingWindowSplitSelection(
                groupID: pendingSelection.groupID,
                preferredMemberID: pendingSelection.activeMemberID
            )
        )

        tabManager.startupRestoreLifecycle.markLoadFinished()
        service.handleTabManagerDataLoaded(windows: [windowState])

        XCTAssertEqual(delegate.focusedSplitGroupIds, [group.id])
        XCTAssertNil(windowState.restorationState.pendingSplitSelection)
        XCTAssertEqual(
            windowState.splitSelection,
            WindowSplitSelection(
                groupID: group.id,
                activeMemberID: .regularTab(second.id)
            )
        )
    }

    func testSetupWindowStateFallsBackToDefaultWhenLoadedSpaceIsMissing() async throws {
        let tabManager = BrowserManager()
        tabManager.startupRestoreLifecycle.markLoadFinished()
        XCTAssertTrue(tabManager.startupRestoreLifecycle.hasLoadedInitialData)
        tabManager.spaceStateOwner.replaceSpaces([])
        tabManager.spaceStateOwner.replaceCurrentSpace(nil)

        let spaceId = UUID()
        let sessionKey = try seedWindowSession(currentSpaceId: spaceId)
        defer { UserDefaults.standard.removeObject(forKey: sessionKey) }

        let windowState = BrowserWindowState(initialWorkspaceTheme: makeVisibleTheme())
        let delegate = TestWindowSessionDelegate(runtime: tabManager)
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

        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let globalProfile = Profile(name: "Global")
        let windowProfile = Profile(name: "Window")
        let globalSpace = Space(name: "Global", profileId: globalProfile.id)
        let windowSpace = Space(name: "Window", profileId: windowProfile.id)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = UUID()
        windowState.currentProfileId = windowProfile.id
        windowState.isShowingEmptyState = true
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)

        browserManager.currentProfile = globalProfile
        browserManager.profileManager.profiles = [globalProfile, windowProfile]
        browserManager.spaceStateOwner.replaceSpaces([globalSpace, windowSpace])
        windowRegistry.register(windowState)

        browserManager.windowStateReconciler.validateWindowStates()

        XCTAssertEqual(windowState.currentSpaceId, windowSpace.id)
        XCTAssertEqual(windowState.currentProfileId, windowProfile.id)
    }

    func testValidateWindowStatesRepairsStaleSpaceFromCurrentTabSpace() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer { UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey) }

        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let globalProfile = Profile(name: "Global")
        let windowProfile = Profile(name: "Window")
        let globalSpace = Space(name: "Global", profileId: globalProfile.id)
        let windowSpace = Space(name: "Window", profileId: windowProfile.id)
        browserManager.currentProfile = globalProfile
        browserManager.profileManager.profiles = [globalProfile, windowProfile]
        browserManager.spaceStateOwner.replaceSpaces([globalSpace, windowSpace])
        let windowTab = browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://window.example",
            in: windowSpace,
            activate: false
        )
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = UUID()
        windowState.currentTabId = windowTab.id
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)

        windowRegistry.register(windowState)

        browserManager.windowStateReconciler.validateWindowStates()

        XCTAssertEqual(windowState.currentSpaceId, windowSpace.id)
        XCTAssertEqual(windowState.currentProfileId, windowProfile.id)
        XCTAssertEqual(windowState.currentTabId, windowTab.id)
    }

    func testValidateWindowStatesDoesNotUseCurrentProfileOrFirstSpaceWithoutWindowContext() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
        defer { UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey) }

        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let globalProfile = Profile(name: "Global")
        let otherProfile = Profile(name: "Other")
        let globalSpace = Space(name: "Global", profileId: globalProfile.id)
        let otherSpace = Space(name: "Other", profileId: otherProfile.id)
        let windowState = BrowserWindowState()
        windowState.currentSpaceId = UUID()
        windowState.isShowingEmptyState = false
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)

        browserManager.currentProfile = globalProfile
        browserManager.profileManager.profiles = [globalProfile, otherProfile]
        browserManager.spaceStateOwner.replaceSpaces([globalSpace, otherSpace])
        windowRegistry.register(windowState)

        browserManager.windowStateReconciler.validateWindowStates()

        XCTAssertNil(windowState.currentSpaceId)
        XCTAssertNil(windowState.currentProfileId)
        XCTAssertTrue(windowState.isShowingEmptyState)
    }

    func testValidateWindowStatesDoesNotMutateUnresolvedInitialSession() {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let pendingSpaceId = UUID()
        let pendingProfileId = UUID()
        let pendingTabId = UUID()
        let windowState = BrowserWindowState(
            awaitsInitialSessionResolution: true
        )
        windowState.currentSpaceId = pendingSpaceId
        windowState.currentProfileId = pendingProfileId
        windowState.currentTabId = pendingTabId
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)

        windowRegistry.register(windowState)

        browserManager.windowStateReconciler.validateWindowStates()

        XCTAssertEqual(windowState.currentSpaceId, pendingSpaceId)
        XCTAssertEqual(windowState.currentProfileId, pendingProfileId)
        XCTAssertEqual(windowState.currentTabId, pendingTabId)
        XCTAssertFalse(windowState.isShowingEmptyState)
    }

    func testValidateWindowStatesPreservesIncognitoContextAndSelection() {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
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
        windowState.replaceEphemeralTabs([ephemeralTab])
        windowState.currentTabId = ephemeralTab.id
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)

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
        browserManager.spaceStateOwner.replaceSpaces([])

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

        browserManager.windowActivation.activate(windowState)

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
        commandPaletteReason: CommandPalettePresentationReason? = nil,
        commandPaletteDraft: CommandPaletteDraftState = CommandPaletteDraftState(text: "", navigateCurrentTab: false)
    ) throws -> String {
        let sessionKey = "SumiTests.windowSession.\(UUID().uuidString)"
        let snapshot = WindowSessionSnapshot(
            currentTabId: currentTabId,
            currentSpaceId: currentSpaceId,
            currentProfileId: nil,
            activeShortcutPinId: activeShortcutPinId,
            activeShortcutPinRole: activeShortcutPinRole,
            isShowingEmptyState: isShowingEmptyState,
            commandPaletteReason: commandPaletteReason,
            activeTabsBySpace: [],
            activeShortcutsBySpace: activeShortcutsBySpace,
            sidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            savedSidebarWidth: Double(BrowserWindowState.sidebarDefaultWidth),
            sidebarContentWidth: Double(BrowserWindowState.sidebarContentWidth(
                for: BrowserWindowState.sidebarDefaultWidth
            )),
            isSidebarVisible: true,
            commandPaletteDraft: commandPaletteDraft
        )
        WindowSessionSnapshotStore(key: sessionKey).persist(snapshot)
        return sessionKey
    }

    private func createSpace(
        named name: String,
        profileID: UUID,
        in browser: BrowserManager
    ) throws -> Space {
        try XCTUnwrap(
            browser.sidebarSpaceLifecycle.createSpace(
                name: name,
                icon: "square",
                profileID: profileID
            )
        )
    }
}

@MainActor
final class TestWindowSessionDelegate:
    WindowSessionSelectionApplying,
    WindowSessionCommandPaletteSanitizing,
    WindowSessionThemeCommitting,
    WindowSessionSplitFocusing {
    let runtime: BrowserManager
    let glanceManager = GlanceManager()
    let shellSelectionService: ShellSelectionService
    var currentProfile: Profile?
    let windowRegistry: WindowRegistry
    private(set) var persistenceComposition: WindowSessionPersistenceTestComposition?
    var lastSessionWindowsStore: LastSessionWindowsStore? {
        persistenceComposition?.lastSessionWindowsStore
    }
    private let themeCoordinator = WorkspaceThemeCoordinator()
    private(set) var committedThemes: [WorkspaceTheme] = []
    private(set) var focusedSplitGroupIds: [UUID] = []
    var onSyncShortcutSelectionState: ((BrowserWindowState) -> Void)?

    init(
        runtime: BrowserManager,
        windowRegistry: WindowRegistry = WindowRegistry()
    ) {
        self.runtime = runtime
        self.windowRegistry = windowRegistry
        self.shellSelectionService = ShellSelectionService(
            splitQuery: WindowSplitQuery(
                splitGroups: runtime.splitGroupStore,
                regularTabs: runtime.regularTabCollectionOwner,
                pins: runtime.shortcutPinCollectionStateOwner,
                liveShortcuts: runtime.liveShortcutTabs,
                windows: windowRegistry,
                previewIsActive: { _ in false }
            )
        )
    }

    func makeRestoreService(
        lastWindowSessionKey: String = "SumiTests.windowSession.\(UUID())",
        snapshotStore: WindowSessionSnapshotStore? = nil
    ) -> WindowSessionRestoreService {
        let store = snapshotStore ?? WindowSessionSnapshotStore(
            key: lastWindowSessionKey
        )
        let scheduler = WindowSessionPersistenceScheduler()
        let snapshotFactory = WindowSessionSnapshotFactory(
            glanceManager: glanceManager
        )
        let persistenceComposition = WindowSessionPersistenceTestComposition(
            snapshotStore: store,
            scheduler: scheduler,
            snapshotFactory: snapshotFactory,
            windows: windowRegistry
        )
        self.persistenceComposition = persistenceComposition
        let spaceResolver = WindowSessionSpaceResolver(
            spaces: runtime.spaceStateOwner,
            membership: runtime.tabCollectionMembershipOwner
        )
        return WindowSessionRestoreService(
            snapshotStore: store,
            persistence: persistenceComposition.coordinator,
            profileReferenceAdmission: runtime.profileReferenceAdmission,
            membership: runtime.tabCollectionMembershipOwner,
            startupRestore: runtime.startupRestoreLifecycle,
            tabStore: runtime.runtimeStore,
            glanceManager: glanceManager,
            spaceResolver: spaceResolver,
            shortcutRestorer: WindowSessionShortcutRestorer(
                pins: runtime.shortcutPinCollectionStateOwner,
                activation: runtime.shortcutPresentationActivation
            ),
            splitRestorer: WindowSessionSplitRestorer(
                groups: runtime.splitGroupStore,
                startupRestore: runtime.startupRestoreLifecycle,
                focus: self
            ),
            themeRestorer: WindowSessionThemeRestorer(
                startupRestore: runtime.startupRestoreLifecycle,
                spaceResolver: spaceResolver,
                themeCommitter: self
            ),
            selectionService: shellSelectionService,
            selection: self,
            commandPaletteSanitizer: self
        )
    }

    func hasValidCurrentSelection(in windowState: BrowserWindowState) -> Bool {
        windowState.currentTabId.map { runtime.tabCollectionMembershipOwner.tab(for: $0) != nil } ?? false
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
        presentNewTabCommandPalette _: Bool
    ) {
        windowState.isShowingEmptyState = true
    }

    func sanitize(in _: BrowserWindowState) { /* no-op */ }

    func syncShortcutSelectionState(for windowState: BrowserWindowState) {
        onSyncShortcutSelectionState?(windowState)
    }

    func commitWorkspaceTheme(_ theme: WorkspaceTheme, for windowState: BrowserWindowState) {
        committedThemes.append(theme)
        themeCoordinator.restore(theme, in: windowState)
    }

    func space(for spaceId: UUID?) -> Space? {
        guard let spaceId else { return nil }
        return runtime.spaceStateOwner.spaces.first { $0.id == spaceId }
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
        if let tab = targetTabId.flatMap({ runtime.tabCollectionMembershipOwner.tab(for: $0) }) {
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
