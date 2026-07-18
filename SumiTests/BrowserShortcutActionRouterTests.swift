import AppKit
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class BrowserShortcutActionRouterTests: XCTestCase {
    func testShortcutDispatchUsesResolvedWindowNewTabSurface() throws {
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
        let appKitWindow = NSWindow()
        windowRegistry.bindAppKitWindow(appKitWindow, to: windowState)

        guard case .browser(let context) = browserManager.shortcutTargetResolver
            .resolve(keyWindow: appKitWindow)
        else { return XCTFail("Expected browser shortcut context") }
        browserManager.shortcutActionRouter.execute(.newTab, in: context)

        XCTAssertTrue(windowState.presentationState.isFloatingBarVisible)
        XCTAssertFalse(browserManager.optionalModules.extensions.hasLoadedRuntime)
    }

    func testContextualActionIsNotAcceptedAsApplicationAction() throws {
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

        XCTAssertFalse(
            browserManager.shortcutActionRouter
                .executeApplicationAction(.newTab)
        )

        XCTAssertEqual(
            browserManager.tabCollectionMembershipOwner.allTabs().count,
            tabCountBefore
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
