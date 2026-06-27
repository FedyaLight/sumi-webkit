import XCTest

@testable import Sumi

@MainActor
final class BrowserActionOwnerTests: XCTestCase {
    func testSidebarFolderActionUsesWindowSpaceBeforeGlobalCurrentSpace() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        harness.browserManager.tabManager.currentSpace = harness.secondarySpace

        harness.browserManager.createFolderInCurrentSpace(in: harness.windowState)

        XCTAssertEqual(
            harness.browserManager.spaceForSidebarActions(in: harness.windowState)?.id,
            harness.primarySpace.id
        )
        XCTAssertEqual(harness.browserManager.tabManager.folders(for: harness.primarySpace.id).count, 1)
        XCTAssertTrue(harness.browserManager.tabManager.folders(for: harness.secondarySpace.id).isEmpty)
    }

    func testGlobalSidebarToggleTargetsOnlyRegisteredWindowWhenNoActiveWindowExists() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness(activateWindow: false)

        XCTAssertNil(harness.windowRegistry.activeWindowId)
        XCTAssertTrue(harness.windowState.isSidebarVisible)

        harness.browserManager.toggleSidebar()
        harness.browserManager.flushPendingWindowSessionPersistence()

        XCTAssertEqual(harness.windowRegistry.activeWindowId, harness.windowState.id)
        XCTAssertFalse(harness.windowState.isSidebarVisible)
    }

    private func makeHarness(activateWindow: Bool = true) -> Harness {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let primarySpace = Space(name: "Primary", profileId: profile.id)
        let secondarySpace = Space(name: "Secondary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [primarySpace, secondarySpace]
        browserManager.tabManager.currentSpace = primarySpace

        windowState.tabManager = browserManager.tabManager
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
