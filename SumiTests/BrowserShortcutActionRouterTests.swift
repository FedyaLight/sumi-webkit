import AppKit
import SumiDomain
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

        XCTAssertTrue(windowState.presentationState.isCommandPaletteVisible)
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

    func testAvailabilityUsesTheExactResolvedWindowContext() throws {
        let windowRegistry = WindowRegistry()
        let browserManager = try makeBrowserManager(
            windowRegistry: windowRegistry
        )
        let windowState = BrowserWindowState()
        windowRegistry.register(windowState)
        let appKitWindow = NSWindow()
        windowRegistry.bindAppKitWindow(appKitWindow, to: windowState)

        guard case .browser(let context) = browserManager.shortcutTargetResolver
            .resolve(keyWindow: appKitWindow) else {
            return XCTFail("Expected browser shortcut context")
        }

        XCTAssertTrue(
            browserManager.shortcutActionRouter.canExecute(
                .newTab,
                in: context
            )
        )
        XCTAssertFalse(
            browserManager.shortcutActionRouter.canExecute(
                .findInPage,
                in: context
            )
        )
    }

    func testCommandPalettePresentsActiveLauncherCloseAsUnload() throws {
        let windowRegistry = WindowRegistry()
        let browserManager = try makeBrowserManager(
            windowRegistry: windowRegistry
        )
        let profile = Profile(name: "Primary")
        let space = Space(name: "Work", profileId: profile.id)
        let windowState = BrowserWindowState()
        browserManager.tabResidenceAuthority
            .establishResidenceSession(on: windowState)
        windowState.currentProfileId = profile.id
        windowState.currentSpaceId = space.id
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.spaceStateOwner.replaceSpaces([space])
        browserManager.spaceStateOwner.replaceCurrentSpace(space)
        windowRegistry.register(windowState)
        let appKitWindow = NSWindow()
        windowRegistry.bindAppKitWindow(appKitWindow, to: windowState)

        let pin = try XCTUnwrap(
            browserManager.shortcutPinStoreOwner.insert(
                ShortcutPin(
                    id: UUID(),
                    role: .spacePinned,
                    spaceId: space.id,
                    index: 0,
                    launchURL: URL(string: "https://launcher.example")!,
                    title: "Launcher"
                ),
                at: 0
            )
        )
        let liveTab = try XCTUnwrap(
            browserManager.shortcutTabMaterializer.materialize(
                pin,
                in: windowState.id,
                currentSpaceId: space.id
            )
        )
        windowState.currentTabId = liveTab.id
        windowState.currentShortcutPinId = pin.id
        windowState.currentShortcutPinRole = .spacePinned

        let shortcuts = KeyboardShortcutManager(
            installEventMonitor: false
        )
        shortcuts.attach(
            actionRouter: browserManager.shortcutActionRouter,
            targetResolver: browserManager.shortcutTargetResolver,
            extensionsModule: browserManager.optionalModules.extensions
        )

        let presentations =
            shortcuts.commandPaletteActionPresentations(
                keyWindow: appKitWindow
            )
        let close = try XCTUnwrap(
            presentations.first(where: { $0.action == .closeTab })
        )
        XCTAssertEqual(close.title, "Unload")
        XCTAssertTrue(
            presentations.contains(where: { $0.action == .unpinTab })
        )
        XCTAssertFalse(
            presentations.contains(where: { $0.action == .pinTab })
        )
    }

    private func makeBrowserManager(
        windowRegistry: WindowRegistry
    ) throws -> BrowserManager {
        BrowserManager(
            windowRegistry: windowRegistry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupContainer()
            )
        )
    }

    private func makeInMemoryStartupContainer() throws -> SumiDatabase {
        try SumiDatabase.inMemory()
    }
}
