import XCTest
import SumiDomain

@testable import Sumi

@MainActor
final class BrowserManagerSidebarActionRoutingTests: XCTestCase {
    func testSidebarFolderActionUsesWindowSpaceBeforeGlobalCurrentSpace() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        harness.browserManager.spaceStateOwner.replaceCurrentSpace(harness.secondarySpace)

        harness.browserManager.chromeBundle.sidebarActionOwner.createFolderInCurrentSpace(in: harness.windowState)

        XCTAssertEqual(
            harness.browserManager.chromeBundle.sidebarActionOwner.spaceForSidebarActions(in: harness.windowState)?.id,
            harness.primarySpace.id
        )
        XCTAssertEqual(harness.browserManager.folderCollectionStateOwner.folders(for: harness.primarySpace.id).count, 1)
        XCTAssertTrue(harness.browserManager.folderCollectionStateOwner.folders(for: harness.secondarySpace.id).isEmpty)
    }

    func testGlobalSidebarToggleTargetsOnlyRegisteredWindowWhenNoActiveWindowExists() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness(activateWindow: false)

        XCTAssertNil(harness.windowRegistry.activeWindowId)
        XCTAssertTrue(harness.windowState.isSidebarVisible)

        harness.browserManager.chromeBundle.sidebarPresentationOwner.toggleSidebar()
        harness.browserManager.windowSessionPersistenceCoordinator.flush()

        XCTAssertEqual(harness.windowRegistry.activeWindowId, harness.windowState.id)
        XCTAssertFalse(harness.windowState.isSidebarVisible)
    }

    func testWorkspaceThemePreviewTargetsOnlyRequestedWindowAndCanRestoreOriginalTheme() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let otherTheme = WorkspaceTheme(gradientTheme: .incognito)
        let otherWindow = BrowserWindowState(initialWorkspaceTheme: otherTheme)
        harness.windowRegistry.register(otherWindow)
        let originalTheme = harness.primarySpace.workspaceTheme
        let draftTheme = SumiWorkspaceThemePresets.rotatingTheme(at: 3)
        let routing = harness.browserManager.composeSidebarSpaceTransitionRoutingOwner()

        routing.previewWorkspaceTheme(draftTheme, in: harness.windowState)

        XCTAssertTrue(harness.windowState.workspaceTheme.visuallyEquals(draftTheme))
        XCTAssertTrue(otherWindow.workspaceTheme.visuallyEquals(otherTheme))
        XCTAssertTrue(harness.primarySpace.workspaceTheme.visuallyEquals(originalTheme))

        routing.previewWorkspaceTheme(originalTheme, in: harness.windowState)

        XCTAssertTrue(harness.windowState.workspaceTheme.visuallyEquals(originalTheme))
        XCTAssertTrue(otherWindow.workspaceTheme.visuallyEquals(otherTheme))
    }

    private func makeHarness(activateWindow: Bool = true) -> Harness {
        let windowRegistry = WindowRegistry()
        let browserManager = BrowserManager(windowRegistry: windowRegistry)
        let profile = Profile(name: "Primary")
        let primarySpace = Space(name: "Primary", profileId: profile.id)
        let secondarySpace = Space(name: "Secondary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([primarySpace, secondarySpace])
        browserManager.spaceStateOwner.replaceCurrentSpace(primarySpace)

        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentSpaceId = primarySpace.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        if activateWindow {
            windowRegistry.setActive(windowState)
        }

        return Harness(
            browserManager: browserManager,
            windowRegistry: windowRegistry,
            windowState: windowState,
            primarySpace: primarySpace,
            secondarySpace: secondarySpace
        )
    }

    private func removePersistedWindowSession() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
    }
}

@MainActor
private struct Harness {
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let windowState: BrowserWindowState
    let primarySpace: Space
    let secondarySpace: Space
}
