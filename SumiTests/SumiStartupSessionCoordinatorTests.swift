import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiStartupSessionCoordinatorTests: XCTestCase {
    func testNothingStartupClearsVisibleSessionAndArchivesManualRestoreSnapshot() throws {
        let harness = try makeHarness(startupMode: .nothing)
        defer { harness.defaults.reset() }

        let regularTab = harness.browserManager.tabManager.createNewTab(
            url: "https://regular.example",
            in: harness.space,
            activate: false
        )
        let pin = makeSpacePin(spaceId: harness.space.id)
        harness.browserManager.tabManager.setSpacePinnedShortcuts([pin], for: harness.space.id)
        let liveTab = harness.browserManager.tabManager.activateShortcutPin(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = .spacePinned
        harness.windowState.selectedShortcutPinForSpace[harness.space.id] = pin.id

        harness.browserManager.applyStartupPolicy(.nothing)

        XCTAssertTrue(harness.browserManager.tabManager.tabs(in: harness.space).isEmpty)
        XCTAssertNil(harness.browserManager.tabManager.shortcutLiveTab(for: pin.id, in: harness.windowState.id))
        XCTAssertNil(harness.windowState.currentTabId)
        XCTAssertNil(harness.windowState.currentShortcutPinId)
        XCTAssertTrue(harness.windowState.isShowingEmptyState)
        XCTAssertEqual(
            harness.browserManager.tabManager.spacePinnedPins(for: harness.space.id).map(\.id),
            [pin.id]
        )
        XCTAssertEqual(
            harness.browserManager.lastSessionWindowsStore.tabSnapshot?.tabs.map(\.id).contains(regularTab.id),
            true
        )
        XCTAssertTrue(harness.browserManager.canOfferStartupLastSessionRestoreShortcut)
    }

    func testSpecificPageStartupOpensExactlyOneConfiguredRegularTabAndArchivesManualRestoreSnapshot() throws {
        let harness = try makeHarness(startupMode: .specificPage, startupPage: "configured.example")
        defer { harness.defaults.reset() }

        let previousTab = harness.browserManager.tabManager.createNewTab(
            url: "https://previous.example",
            in: harness.space,
            activate: false
        )
        harness.windowState.currentTabId = previousTab.id

        harness.browserManager.applyStartupPolicy(.specificPage)

        let tabs = harness.browserManager.tabManager.tabs(in: harness.space)
        XCTAssertEqual(tabs.count, 1)
        XCTAssertEqual(tabs.first?.url.absoluteString, "https://configured.example")
        XCTAssertEqual(harness.windowState.currentTabId, tabs.first?.id)
        XCTAssertFalse(harness.windowState.isShowingEmptyState)
        XCTAssertEqual(
            harness.browserManager.lastSessionWindowsStore.tabSnapshot?.tabs.map(\.id).contains(previousTab.id),
            true
        )
        XCTAssertTrue(harness.browserManager.canOfferStartupLastSessionRestoreShortcut)
    }

    func testRestorePreviousSessionPolicyDoesNotClearRegularTabsOrLauncherLiveInstances() throws {
        let harness = try makeHarness(startupMode: .restorePreviousSession)
        defer { harness.defaults.reset() }

        let regularTab = harness.browserManager.tabManager.createNewTab(
            url: "https://regular.example",
            in: harness.space,
            activate: false
        )
        let pin = makeSpacePin(spaceId: harness.space.id)
        harness.browserManager.tabManager.setSpacePinnedShortcuts([pin], for: harness.space.id)
        let liveTab = harness.browserManager.tabManager.activateShortcutPin(
            pin,
            in: harness.windowState.id,
            currentSpaceId: harness.space.id
        )
        harness.windowState.currentTabId = liveTab.id
        harness.windowState.currentShortcutPinId = pin.id
        harness.windowState.currentShortcutPinRole = .spacePinned

        harness.browserManager.applyStartupPolicy(.restorePreviousSession)

        XCTAssertEqual(harness.browserManager.tabManager.tabs(in: harness.space).map(\.id), [regularTab.id])
        XCTAssertEqual(
            harness.browserManager.tabManager.shortcutLiveTab(for: pin.id, in: harness.windowState.id)?.id,
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
            existingSessions: [],
            hasStartupWindow: true
        )

        XCTAssertEqual(plan.primarySnapshotForStartupWindow, first)
        XCTAssertEqual(plan.additionalSnapshots, [second])
    }

    func testStartupRestorationDoesNotReapplySnapshotAlreadyInExistingWindow() {
        let first = makeLastSessionWindowSnapshot(sidebarWidth: 320)
        let second = makeLastSessionWindowSnapshot(sidebarWidth: 420)
        let plan = StartupWindowRestorationPlanner.plan(
            archivedSnapshots: [first, second],
            existingSessions: [first.session],
            hasStartupWindow: true
        )

        XCTAssertNil(plan.primarySnapshotForStartupWindow)
        XCTAssertEqual(plan.additionalSnapshots, [second])
    }

    private func makeHarness(
        startupMode: SumiStartupMode,
        startupPage: String = SumiStartupPageURL.defaultURLString
    ) throws -> StartupPolicyHarness {
        let defaults = TestDefaultsHarness()
        let settings = SumiSettingsService(userDefaults: defaults.defaults)
        settings.startupMode = startupMode
        settings.startupPageURLString = startupPage

        let browserManager = BrowserManager()
        let tabManager = try makeInMemoryTabManager()
        tabManager.browserManager = browserManager
        tabManager.sumiSettings = settings
        browserManager.tabManager = tabManager
        browserManager.sumiSettings = settings
        browserManager.lastSessionWindowsStore = LastSessionWindowsStore(userDefaults: defaults.defaults)
        browserManager.startupLastSessionWindowSnapshots = []
        browserManager.startupLastSessionTabSnapshot = nil
        browserManager.didConsumeStartupLastSessionRestoreOffer = true

        let windowRegistry = WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let space = Space(name: "Primary")
        tabManager.spaces = [space]
        tabManager.currentSpace = space
        tabManager.setTabs([], for: space.id)
        tabManager.markInitialDataLoadFinished()

        let windowState = BrowserWindowState()
        windowState.tabManager = tabManager
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

    private func makeInMemoryTabManager() throws -> TabManager {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return TabManager(context: container.mainContext, loadPersistedState: false)
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
                urlBarDraft: URLBarDraftState(text: "", navigateCurrentTab: false),
                splitSession: nil
            )
        )
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
