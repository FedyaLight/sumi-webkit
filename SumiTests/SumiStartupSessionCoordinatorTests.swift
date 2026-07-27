import SumiDomain
import SumiWebRuntime
import XCTest

@testable import Sumi

@MainActor
final class SumiStartupSessionCoordinatorTests: XCTestCase {
    func testNothingStartupClearsVisibleSessionAndArchivesManualRestoreSnapshot() throws {
        let harness = try makeHarness(startupMode: .nothing)
        defer { harness.defaults.reset() }

        let regularTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://regular.example",
            in: harness.space,
            activate: false
        )
        let pin = makeSpacePin(spaceId: harness.space.id)
        harness.browserManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: harness.space.id)
        let liveTab = harness.browserManager.shortcutTabMaterializer.materialize(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )!
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = .spacePinned
        harness.windowState.selectedShortcutPinForSpace[harness.space.id] = pin.id
        harness.windowState.restorationState.restoredSessionWindowID = UUID()

        harness.browserManager.profileLifecycleBundle.startupPolicy.apply(.nothing)

        XCTAssertTrue(harness.browserManager.regularTabCollectionOwner.tabs(in: harness.space).isEmpty)
        XCTAssertNil(harness.browserManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        XCTAssertNil(harness.windowState.currentTabId)
        XCTAssertNil(harness.windowState.currentShortcutPinId)
        XCTAssertNil(harness.windowState.restorationState.restoredSessionWindowID)
        XCTAssertTrue(harness.windowState.isShowingEmptyState)
        XCTAssertTrue(harness.windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(harness.windowState.commandPalettePresentationReason, .emptySpace)
        XCTAssertEqual(
            harness.browserManager.shortcutPinCollectionStateOwner.spacePinnedPins(for: harness.space.id).map(\.id),
            [pin.id]
        )
        XCTAssertEqual(
            harness.browserManager.lastSessionWindowsStore.tabSnapshot?.tabs.map(\.id).contains(regularTab.id),
            true
        )
        XCTAssertNotEqual(
            harness.browserManager.lastSessionWindowsStore.snapshots.first?.id,
            harness.windowState.id
        )
        XCTAssertTrue(harness.browserManager.windowSessionBundle.sessionRecovery.canOfferStartupSessionRestoreShortcut)
    }

    func testNothingStartupInitializesWindowContextBeforeFirstShortcutClick() throws {
        let harness = try makeHarness(startupMode: .nothing)
        defer { harness.defaults.reset() }
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let essential = ShortcutPin(
            id: UUID(),
            role: .essential,
            profileId: profile.id,
            index: 0,
            launchURL: URL(string: "https://essential.example")!,
            title: "Essential"
        )
        let spacePin = makeSpacePin(spaceId: space.id)

        harness.browserManager.profileManager.profiles = [profile]
        harness.browserManager.currentProfile = profile
        harness.browserManager.spaceStateOwner.replaceSpaces([space])
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(space)
        harness.browserManager.structuralCollectionMutationOwner.setTabs(
            [],
            for: space.id
        )
        harness.browserManager.structuralCollectionMutationOwner.setPinnedTabs(
            [essential],
            for: profile.id
        )
        harness.browserManager.structuralCollectionMutationOwner
            .setSpacePinnedShortcuts([spacePin], for: space.id)
        harness.windowState.currentSpaceId = nil
        harness.windowState.currentProfileId = nil

        harness.browserManager.profileLifecycleBundle.startupPolicy.apply(.nothing)

        XCTAssertEqual(harness.windowState.currentSpaceId, space.id)
        XCTAssertEqual(harness.windowState.currentProfileId, profile.id)

        let execution = SidebarPinExecutionCommands(
            runtime: harness.browserManager.runtimePortConnection,
            windows: SidebarWindowIdentityQuery(
                registry: harness.windowRegistry
            ),
            pins: harness.browserManager.shortcutPinCollectionStateOwner,
            materializer: harness.browserManager.shortcutTabMaterializer,
            profiles: harness.browserManager.shortcutExecutionProfileAssignments
        )
        let essentialTab = try XCTUnwrap(
            execution.materialize(
                essential,
                in: harness.windowState,
                currentSpaceID: harness.windowState.currentSpaceId
            )
        )
        XCTAssertTrue(
            harness.browserManager.browserTabSelection.selectTab(
                essentialTab,
                in: harness.windowState,
                loadPolicy: .deferred
            ).wasCommitted
        )
        XCTAssertEqual(harness.windowState.currentTabId, essentialTab.id)

        let spacePinnedTab = try XCTUnwrap(
            execution.materialize(
                spacePin,
                in: harness.windowState,
                currentSpaceID: space.id
            )
        )
        XCTAssertTrue(
            harness.browserManager.browserTabSelection.selectTab(
                spacePinnedTab,
                in: harness.windowState,
                loadPolicy: .deferred
            ).wasCommitted
        )
        XCTAssertEqual(harness.windowState.currentTabId, spacePinnedTab.id)
    }

    func testSpecificPageStartupOpensExactlyOneConfiguredRegularTabAndArchivesManualRestoreSnapshot() throws {
        let harness = try makeHarness(startupMode: .specificPage, startupPage: "configured.example")
        defer { harness.defaults.reset() }

        let previousTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://previous.example",
            in: harness.space,
            activate: false
        )
        harness.windowState.currentTabId = previousTab.id

        harness.browserManager.profileLifecycleBundle.startupPolicy.apply(.specificPage)

        let tabs = harness.browserManager.regularTabCollectionOwner.tabs(in: harness.space)
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.first?.url.absoluteString, "https://configured.example")
        XCTAssertEqual(harness.windowState.currentTabId, tabs.first?.id)
        XCTAssertFalse(harness.windowState.isShowingEmptyState)
        XCTAssertFalse(harness.windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(harness.windowState.commandPalettePresentationReason, .none)
        XCTAssertEqual(
            harness.browserManager.lastSessionWindowsStore.tabSnapshot?.tabs.map(\.id).contains(previousTab.id),
            true
        )
        XCTAssertTrue(harness.browserManager.windowSessionBundle.sessionRecovery.canOfferStartupSessionRestoreShortcut)
    }

    func testSpecificPageStartupWithStaleWindowSpaceDoesNotUseGlobalCurrentSpaceOrFirstSpace() throws {
        let harness = try makeHarness(startupMode: .specificPage, startupPage: "configured.example")
        defer { harness.defaults.reset() }
        let secondarySpace = Space(name: "Secondary")
        harness.browserManager.spaceStateOwner.append(secondarySpace)
        harness.browserManager.structuralCollectionMutationOwner.setTabs([], for: secondarySpace.id)
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(secondarySpace)
        harness.windowState.currentSpaceId = UUID()
        harness.windowState.currentProfileId = nil

        harness.browserManager.profileLifecycleBundle.startupPolicy.apply(.specificPage)

        let primaryTabs = harness.browserManager.regularTabCollectionOwner.tabs(in: harness.space)
        XCTAssertTrue(primaryTabs.isEmpty)
        XCTAssertTrue(harness.browserManager.regularTabCollectionOwner.tabs(in: secondarySpace).isEmpty)
        XCTAssertNil(harness.windowState.currentSpaceId)
        XCTAssertNil(harness.windowState.currentTabId)
        XCTAssertTrue(harness.windowState.isShowingEmptyState)
        XCTAssertTrue(harness.windowState.presentationState.isCommandPaletteVisible)
        XCTAssertEqual(harness.windowState.commandPalettePresentationReason, .emptySpace)
    }

    func testSpecificPageStartupWithWindowProfileRepairsStaleSpace() throws {
        let harness = try makeHarness(startupMode: .specificPage, startupPage: "configured.example")
        defer { harness.defaults.reset() }
        let fallbackProfile = Profile(name: "Fallback")
        let windowProfile = Profile(name: "Window")
        let fallbackSpace = Space(name: "Fallback", profileId: fallbackProfile.id)
        let windowProfileSpace = Space(name: "Window", profileId: windowProfile.id)
        harness.browserManager.profileManager.profiles = [fallbackProfile, windowProfile]
        harness.browserManager.currentProfile = fallbackProfile
        harness.browserManager.spaceStateOwner.replaceSpaces([fallbackSpace, windowProfileSpace])
        harness.browserManager.structuralCollectionMutationOwner.setTabs([], for: fallbackSpace.id)
        harness.browserManager.structuralCollectionMutationOwner.setTabs([], for: windowProfileSpace.id)
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(fallbackSpace)
        harness.windowState.currentSpaceId = UUID()
        harness.windowState.currentProfileId = windowProfile.id

        harness.browserManager.profileLifecycleBundle.startupPolicy.apply(.specificPage)

        let windowProfileTabs = harness.browserManager.regularTabCollectionOwner.tabs(in: windowProfileSpace)
        XCTAssertEqual(windowProfileTabs.count, 1)
        XCTAssertEqual(windowProfileTabs.first?.url.absoluteString, "https://configured.example")
        XCTAssertTrue(harness.browserManager.regularTabCollectionOwner.tabs(in: fallbackSpace).isEmpty)
        XCTAssertEqual(harness.windowState.currentSpaceId, windowProfileSpace.id)
        XCTAssertEqual(harness.windowState.currentProfileId, windowProfile.id)
    }

    func testSpecificPageStartupWithStaleProfileDoesNotUseLiveCurrentProfileOrFirstSpace() throws {
        let harness = try makeHarness(startupMode: .specificPage, startupPage: "configured.example")
        defer { harness.defaults.reset() }
        let fallbackProfile = Profile(name: "Fallback")
        let currentProfile = Profile(name: "Current")
        let fallbackSpace = Space(name: "Fallback", profileId: fallbackProfile.id)
        let currentProfileSpace = Space(name: "Current", profileId: currentProfile.id)
        harness.browserManager.profileManager.profiles = [fallbackProfile, currentProfile]
        harness.browserManager.currentProfile = currentProfile
        harness.browserManager.spaceStateOwner.replaceSpaces([fallbackSpace, currentProfileSpace])
        harness.browserManager.structuralCollectionMutationOwner.setTabs([], for: fallbackSpace.id)
        harness.browserManager.structuralCollectionMutationOwner.setTabs([], for: currentProfileSpace.id)
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(fallbackSpace)
        harness.windowState.currentSpaceId = UUID()
        harness.windowState.currentProfileId = UUID()

        harness.browserManager.profileLifecycleBundle.startupPolicy.apply(.specificPage)

        let currentProfileTabs = harness.browserManager.regularTabCollectionOwner.tabs(in: currentProfileSpace)
        XCTAssertTrue(currentProfileTabs.isEmpty)
        XCTAssertTrue(harness.browserManager.regularTabCollectionOwner.tabs(in: fallbackSpace).isEmpty)
        XCTAssertNil(harness.windowState.currentSpaceId)
        XCTAssertNil(harness.windowState.currentProfileId)
        XCTAssertNil(harness.windowState.currentTabId)
        XCTAssertTrue(harness.windowState.isShowingEmptyState)
    }

    func testSpecificPageStartupWithMissingSpaceAndStaleProfileFailsClosed() throws {
        let harness = try makeHarness(startupMode: .specificPage, startupPage: "configured.example")
        defer { harness.defaults.reset() }
        let currentProfile = Profile(name: "Current")
        let currentProfileSpace = Space(name: "Current", profileId: currentProfile.id)
        harness.browserManager.profileManager.profiles = [currentProfile]
        harness.browserManager.currentProfile = currentProfile
        harness.browserManager.spaceStateOwner.replaceSpaces([currentProfileSpace])
        harness.browserManager.structuralCollectionMutationOwner.setTabs([], for: currentProfileSpace.id)
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(currentProfileSpace)
        harness.windowState.currentSpaceId = nil
        harness.windowState.currentProfileId = UUID()

        harness.browserManager.profileLifecycleBundle.startupPolicy.apply(.specificPage)

        XCTAssertTrue(
            harness.browserManager.regularTabCollectionOwner.tabs(in: currentProfileSpace).isEmpty
        )
        XCTAssertNil(harness.windowState.currentSpaceId)
        XCTAssertNil(harness.windowState.currentProfileId)
        XCTAssertNil(harness.windowState.currentTabId)
        XCTAssertTrue(harness.windowState.isShowingEmptyState)
    }

    func testCleanStartupDismissesGlanceAndReleasesPreviewWebView() throws {
        let harness = try makeHarness(startupMode: .nothing)
        defer { harness.defaults.reset() }

        let previousTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://previous.example",
            in: harness.space,
            activate: false
        )
        harness.windowState.currentTabId = previousTab.id

        harness.browserManager.glanceManager.presentExternalURL(
            URL(string: "https://glance.example/page")!,
            from: previousTab
        )
        let session = try XCTUnwrap(harness.browserManager.glanceManager.currentSession)
        let previewTab = session.previewTab
        XCTAssertNotNil(
            previewTab.ensureUntrackedNormalWebView(
                reason: "SumiStartupSessionCoordinatorTests.glancePreview"
            )
        )

        harness.browserManager.profileLifecycleBundle.startupPolicy.apply(.nothing)

        XCTAssertNil(harness.browserManager.glanceManager.currentSession)
        XCTAssertEqual(harness.browserManager.glanceManager.phase, .idle)
        XCTAssertFalse(harness.browserManager.glanceManager.isActive)
        XCTAssertNil(previewTab.resolvedCurrentWebView())
        XCTAssertNil(previewTab.resolvedPrimaryWindowId())
    }

    func testRestorePreviousSessionPolicyDoesNotClearRegularTabsOrLauncherLiveInstances() throws {
        let harness = try makeHarness(startupMode: .restorePreviousSession)
        defer { harness.defaults.reset() }

        let regularTab = harness.browserManager.regularTabLifecycleOwner.createNewTab(
            url: "https://regular.example",
            in: harness.space,
            activate: false
        )
        let pin = makeSpacePin(spaceId: harness.space.id)
        harness.browserManager.structuralCollectionMutationOwner.setSpacePinnedShortcuts([pin], for: harness.space.id)
        let liveTab = harness.browserManager.shortcutTabMaterializer.materialize(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )!
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = .spacePinned

        harness.browserManager.profileLifecycleBundle.startupPolicy.apply(.restorePreviousSession)

        XCTAssertEqual(harness.browserManager.regularTabCollectionOwner.tabs(in: harness.space).map(\.id), [regularTab.id])
        XCTAssertEqual(
            harness.browserManager.shortcutPresentationOwner.shortcutLiveTab(for: pin.id, in: harness.windowState.id)?.id,
            liveTab.id
        )
        XCTAssertEqual(harness.windowState.currentTabId, liveTab.id)
        XCTAssertEqual(harness.windowState.currentShortcutPinId, pin.id)
        XCTAssertNil(harness.browserManager.lastSessionWindowsStore.tabSnapshot)
    }

    func testStartupRestorationUsesLaunchWindowForFirstArchivedSnapshot() {
        let first = makeLastSessionWindowSnapshot(sidebarWidth: 320)
        let second = makeLastSessionWindowSnapshot(sidebarWidth: 420)
        let plan = StartupWindowRestorationPlanner.plan(
            archivedSnapshots: [first, second],
            existingWindowIDs: [],
            hasStartupWindow: true
        )

        XCTAssertEqual(plan.primarySnapshotForStartupWindow, first)
        XCTAssertEqual(plan.additionalSnapshots, [second])
    }

    func testRestorePreviousSessionAssignsArchiveIdentityToLaunchWindow() async throws {
        let harness = try makeHarness(startupMode: .restorePreviousSession)
        defer { harness.defaults.reset() }
        let archived = makeLastSessionWindowSnapshot(sidebarWidth: 320)
        harness.browserManager.lastSessionWindowsStore.updateSnapshots([archived])
        harness.browserManager.startupSessionRestoreOwner.reload(
            from: harness.browserManager.lastSessionWindowsStore
        )

        harness.browserManager.profileLifecycleBundle.startupPolicy
            .apply(.restorePreviousSession)

        await waitUntil {
            harness.windowState.restorationState.restoredSessionWindowID == archived.id
        }
        XCTAssertEqual(harness.windowState.restorationState.restoredSessionWindowID, archived.id)
    }

    func testStartupRestorationDoesNotReapplySnapshotAlreadyInExistingWindow() {
        let first = makeLastSessionWindowSnapshot(sidebarWidth: 320)
        let second = makeLastSessionWindowSnapshot(sidebarWidth: 420)
        let plan = StartupWindowRestorationPlanner.plan(
            archivedSnapshots: [first, second],
            existingWindowIDs: [first.id],
            hasStartupWindow: true,
            startupWindowArchiveID: first.id
        )

        XCTAssertNil(plan.primarySnapshotForStartupWindow)
        XCTAssertEqual(plan.additionalSnapshots, [second])
    }

    func testStartupRestorationKeepsDifferentWindowIDsWithIdenticalSessions() {
        let first = makeLastSessionWindowSnapshot(sidebarWidth: 320)
        let second = LastSessionWindowSnapshot(id: UUID(), session: first.session)
        let plan = StartupWindowRestorationPlanner.plan(
            archivedSnapshots: [first, second],
            existingWindowIDs: [first.id],
            hasStartupWindow: true,
            startupWindowArchiveID: first.id
        )

        XCTAssertNil(plan.primarySnapshotForStartupWindow)
        XCTAssertEqual(plan.additionalSnapshots, [second])
    }

    func testBlankLaunchWindowReceivesFirstMissingSnapshotDuringPartialRestore() {
        let first = makeLastSessionWindowSnapshot(sidebarWidth: 320)
        let alreadyOpen = makeLastSessionWindowSnapshot(sidebarWidth: 420)
        let third = makeLastSessionWindowSnapshot(sidebarWidth: 520)

        let plan = StartupWindowRestorationPlanner.plan(
            archivedSnapshots: [first, alreadyOpen, third],
            existingWindowIDs: [alreadyOpen.id],
            hasStartupWindow: true,
            startupWindowArchiveID: nil
        )

        XCTAssertEqual(plan.primarySnapshotForStartupWindow, first)
        XCTAssertEqual(plan.additionalSnapshots, [third])
    }

    private func makeHarness(
        startupMode: SumiStartupMode,
        startupPage: String = SumiStartupPageURL.defaultURLString
    ) throws -> StartupPolicyHarness {
        let defaults = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: defaults.defaults)
        settings.startupMode = startupMode
        settings.startupPageURLString = startupPage

        let webViewSessions = WebViewSessionRepository()
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(
            webViewSessions: webViewSessions,
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupDatabase()
            ),
            dataServices: .unavailable()
        )
        let tabManager = browserManager
        browserManager.sumiSettings = settings
        browserManager.lastSessionWindowsStore = LastSessionWindowsStore()

        let space = Space(name: "Primary")
        tabManager.spaceStateOwner.replaceSpaces([space])
        tabManager.spaceStateOwner.replaceCurrentSpace(space)
        tabManager.structuralCollectionMutationOwner.setTabs([], for: space.id)
        tabManager.startupRestoreLifecycle.markLoadFinished()

        let windowState = BrowserWindowState()
        windowState.currentSpaceId = space.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return StartupPolicyHarness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            settings: settings,
            windowState: windowState,
            space: space,
            defaults: defaults
        )
    }

    private func makeSpacePin(spaceId: UUID) -> ShortcutPin {
        ShortcutPin(
            id: UUID(),
            role: .spacePinned,
            profileId: nil,
            spaceId: spaceId,
            index: 0,
            folderId: nil,
            launchURL: URL(string: "https://launcher.example")!,
            title: "Launcher",
            iconAsset: nil
        )
    }

    private func makeLastSessionWindowSnapshot(sidebarWidth: Double) -> LastSessionWindowSnapshot {
        LastSessionWindowSnapshot(
            id: UUID(),
            session: WindowSessionSnapshot(
                currentTabId: nil,
                currentSpaceId: UUID(),
                currentProfileId: nil,
                activeShortcutPinId: nil,
                activeShortcutPinRole: nil,
                isShowingEmptyState: true,
                commandPaletteReason: .emptySpace,
                activeTabsBySpace: [],
                activeShortcutsBySpace: [],
                sidebarWidth: sidebarWidth,
                savedSidebarWidth: sidebarWidth,
                sidebarContentWidth: sidebarWidth - Double(BrowserWindowState.sidebarHorizontalPadding),
                isSidebarVisible: true,
                commandPaletteDraft: CommandPaletteDraftState(text: "", navigateCurrentTab: false)
            )
        )
    }

    private func waitUntil(
        _ predicate: @MainActor () -> Bool
    ) async {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(2))
        while predicate() == false, clock.now < deadline {
            await Task.yield()
        }
        XCTAssertTrue(predicate())
    }
}

@MainActor
private struct StartupPolicyHarness {
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let settings: SumiSettingsService
    let windowState: BrowserWindowState
    let space: Space
    let defaults: TestDefaultsHarness
}
