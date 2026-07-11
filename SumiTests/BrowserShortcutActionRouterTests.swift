import AppKit
import Foundation
import SwiftData
import XCTest

@testable import Sumi
import SumiDomain

/// Shortcut routing owns the keyboard command handler: dispatch reaches the
/// handler through the router's injected capability, never by resolving an
/// owner back through the BrowserManager façade.
@MainActor
final class BrowserShortcutActionRouterTests: XCTestCase {
    func testShortcutDispatchReachesInjectedKeyboardCommandCapability() {
        var events: [String] = []
        let windowState = BrowserWindowState()
        let keyboardShortcuts = makeKeyboardCommandOwner(
            activeWindow: { windowState },
            openNewTabOrFloatingBar: { _ in events.append("openNewTabOrFloatingBar") },
            createNewTab: { events.append("createNewTab") }
        )
        let router = BrowserShortcutActionRouter(
            dependencies: makeDependencies(keyboardShortcuts: { keyboardShortcuts })
        )
        let dispatcher = ShortcutActionDispatcher()
        dispatcher.actionRouter = router

        dispatcher.execute(.newTab)

        XCTAssertEqual(events, ["openNewTabOrFloatingBar"])
    }

    func testLiveShortcutDispatchCreatesTabWithoutBrowserManagerFacadeLookup() throws {
        let browserManager = try makeBrowserManager()
        browserManager.bindTestWebViewCoordinator()
        _ = browserManager.tabManager.spaceStateOwner.currentSpace
            ?? browserManager.tabManager.spaceServices.catalog.createSpace(name: "Shortcut Routing")
        let dispatcher = ShortcutActionDispatcher()
        dispatcher.actionRouter = browserManager.shortcutActionRouter
        let tabCountBefore = browserManager.tabManager
            .tabCollectionMembershipOwner.allTabs().count

        dispatcher.execute(.newTab)

        // No active window is registered, so the handler's fallback path must
        // create a regular tab through the live tab-opening capability.
        XCTAssertEqual(
            browserManager.tabManager.tabCollectionMembershipOwner.allTabs().count,
            tabCountBefore + 1
        )
        // Command routing must stay zero-cost for disabled optional modules.
        XCTAssertFalse(browserManager.optionalModules.extensions.hasLoadedRuntime)
        XCTAssertFalse(browserManager.optionalModules.userscripts.hasLoadedRuntime)
    }

    private func makeDependencies(
        keyboardShortcuts: @escaping @MainActor () -> BrowserKeyboardShortcutCommandOwner?
    ) -> BrowserShortcutActionRouter.Dependencies {
        BrowserShortcutActionRouter.Dependencies(
            keyboardShortcuts: keyboardShortcuts,
            historyNavigation: { nil },
            activePageResolver: { nil },
            activePageCommands: { nil },
            zoomCommands: { nil },
            windowShellCommands: { nil },
            pagePrivacyCommands: { nil },
            chromePopovers: { nil },
            dialogs: { nil },
            sessionRecovery: { nil },
            themeEditor: { nil },
            floatingBarPresentation: { nil },
            findManager: { nil },
            showFindBar: {},
            closeCurrentTab: {},
            duplicateCurrentTab: {},
            toggleSidebar: {}
        )
    }

    private func makeKeyboardCommandOwner(
        activeWindow: @escaping @MainActor () -> BrowserWindowState?,
        openNewTabOrFloatingBar: @escaping @MainActor (BrowserWindowState) -> Void,
        createNewTab: @escaping @MainActor () -> Void
    ) -> BrowserKeyboardShortcutCommandOwner {
        BrowserKeyboardShortcutCommandOwner(
            tabSelection: .init(
                activeWindow: activeWindow,
                createNewTab: createNewTab,
                openNewTabOrFloatingBar: openNewTabOrFloatingBar,
                tabsForDisplay: { _ in [] },
                currentTab: { _ in nil },
                selectTab: { _, _ in }
            ),
            spaceSplit: .init(
                isSplit: { _ in false },
                setSplitLayoutKind: { _, _ in },
                enterSplitWithTab: { _, _ in },
                unsplitActiveGroup: { _ in },
                createEmptySplit: { _ in },
                spaces: { [] },
                setActiveSpace: { _, _ in },
                setAllFoldersOpen: { _, _ in },
                persistWindowSession: { _ in }
            ),
            reader: .init(
                activePage: { nil },
                toggleReaderMode: { _, _ in }
            )
        )
    }

    private func makeBrowserManager() throws -> BrowserManager {
        BrowserManager(
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
