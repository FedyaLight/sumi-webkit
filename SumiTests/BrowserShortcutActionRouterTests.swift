import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class BrowserShortcutActionRouterTests: XCTestCase {
    func testShortcutDispatchUsesActiveWindowNewTabSurface() throws {
        let windowRegistry = WindowRegistry()
        let browserManager = try makeBrowserManager(
            windowRegistry: windowRegistry
        )
        let profile = Profile(name: "Primary")
        let space = Space(name: "Work", profileId: profile.id)
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: windowState)
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        browserManager.shortcutActionRouter.execute(.newTab)

        XCTAssertTrue(windowState.presentationState.isFloatingBarVisible)
        XCTAssertFalse(browserManager.optionalModules.extensions.hasLoadedRuntime)
    }

    func testShortcutDispatchCreatesTabWhenNoWindowIsRegistered() throws {
        let browserManager = try makeBrowserManager(
            windowRegistry: WindowRegistry()
        )
        _ = browserManager.spaceStateOwner.currentSpace
            ?? installTestSpace(
                in: browserManager.spaceStateOwner,
                name: "Shortcut Routing"
            )
        let tabCountBefore = browserManager.tabCollectionMembershipOwner
            .allTabs().count

        browserManager.shortcutActionRouter.execute(.newTab)

        XCTAssertEqual(
            browserManager.tabCollectionMembershipOwner.allTabs().count,
            tabCountBefore + 1
        )
        XCTAssertFalse(browserManager.optionalModules.extensions.hasLoadedRuntime)
    }

    private func makeBrowserManager(
        windowRegistry: WindowRegistry
    ) throws -> BrowserManager {
        BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupContainer()
            )
        )
    }

    private func makeInMemoryStartupContainer() throws -> ModelContainer {
        try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
    }
}
