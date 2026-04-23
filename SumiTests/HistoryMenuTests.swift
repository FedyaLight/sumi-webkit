import AppKit
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class HistoryMenuTests: XCTestCase {
    override func tearDown() {
        Tab.clearFaviconCache()
        super.tearDown()
    }

    func testHistoryMenuBuildsDDGStyleStructureAndRecentVisitIcons() async throws {
        let harness = try makeHarness()
        let url = URL(string: "https://example.com")!
        cacheFavicon(for: url)

        try await harness.browserManager.historyManager.store.recordVisit(
            url: url,
            title: "Example",
            visitedAt: Date(),
            profileId: harness.profile.id
        )
        await harness.browserManager.historyManager.refresh()

        let menu = SumiHistoryMenu(
            browserManager: harness.browserManager,
            shortcutManager: nil,
            actionTarget: nil
        )
        menu.update()

        XCTAssertNotNil(menu.items.first(where: { $0.title == "Back" }))
        XCTAssertNotNil(menu.items.first(where: { $0.title == "Forward" }))
        XCTAssertNotNil(menu.items.first(where: { $0.title == "Recently Closed" }))
        XCTAssertNotNil(menu.items.first(where: { $0.title == "Show All History" }))
        XCTAssertNotNil(menu.items.first(where: { $0.title == "Clear All History" }))

        let recentVisitItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Example" }))
        XCTAssertNotNil(recentVisitItem.image)
    }

    func testRecentlyClosedSubmenuShowsIconForClosedTab() throws {
        let harness = try makeHarness()
        let url = URL(string: "https://example.org")!
        cacheFavicon(for: url)

        let tab = Tab(url: url, name: "Example Org", skipFaviconFetch: true)
        harness.browserManager.recentlyClosedManager.captureClosedTab(
            tab,
            sourceSpaceId: harness.space.id,
            currentURL: tab.url,
            canGoBack: false,
            canGoForward: false
        )

        let menu = SumiHistoryMenu(
            browserManager: harness.browserManager,
            shortcutManager: nil,
            actionTarget: nil
        )
        menu.update()

        let recentlyClosedItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Recently Closed" }))
        let submenu = try XCTUnwrap(recentlyClosedItem.submenu)
        let restoredItem = try XCTUnwrap(submenu.items.first(where: { $0.title == "Example Org" }))
        XCTAssertNotNil(restoredItem.image)
    }

    func testInstallerReplacesExistingHistoryAnchorSubmenu() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let mainMenu = NSMenu(title: "Main")
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        historyItem.submenu = NSMenu(title: "SwiftUI Placeholder")
        mainMenu.addItem(NSMenuItem(title: "File", action: nil, keyEquivalent: ""))
        mainMenu.addItem(historyItem)
        mainMenu.addItem(NSMenuItem(title: "Window", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = mainMenu

        let harness = try makeHarness()
        let shortcutManager = KeyboardShortcutManager()
        let actionTarget = NSObject()
        let installer = SumiHistoryMenuInstaller()
        installer.browserManager = harness.browserManager
        installer.shortcutManager = shortcutManager
        installer.actionTarget = actionTarget

        installer.installOrUpdateIfNeeded()

        let installedMenu = try XCTUnwrap(historyItem.submenu as? SumiHistoryMenu)
        XCTAssertTrue(installedMenu.browserManager === harness.browserManager)
        XCTAssertTrue(installedMenu.shortcutManager === shortcutManager)
        XCTAssertTrue(installedMenu.actionTarget === actionTarget)
    }

    func testInstallerInsertsHistoryBeforeExtensionsWhenAnchorIsMissing() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let mainMenu = NSMenu(title: "Main")
        mainMenu.addItem(NSMenuItem(title: "File", action: nil, keyEquivalent: ""))
        mainMenu.addItem(NSMenuItem(title: "Window", action: nil, keyEquivalent: ""))
        mainMenu.addItem(NSMenuItem(title: "Extensions", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = mainMenu

        let installer = SumiHistoryMenuInstaller()
        installer.installOrUpdateIfNeeded()

        XCTAssertEqual(mainMenu.items.map(\.title), ["File", "Window", "History", "Extensions"])
        XCTAssertTrue(mainMenu.items[2].submenu is SumiHistoryMenu)
    }

    func testInstallerUpdatesExistingHistoryMenuWithoutDuplicatingTopLevelItem() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let mainMenu = NSMenu(title: "Main")
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        mainMenu.addItem(NSMenuItem(title: "File", action: nil, keyEquivalent: ""))
        mainMenu.addItem(historyItem)
        mainMenu.addItem(NSMenuItem(title: "Window", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = mainMenu

        let firstHarness = try makeHarness()
        let secondHarness = try makeHarness()
        let installer = SumiHistoryMenuInstaller()
        installer.browserManager = firstHarness.browserManager
        installer.installOrUpdateIfNeeded()

        let originalSubmenu = try XCTUnwrap(historyItem.submenu as? SumiHistoryMenu)

        installer.browserManager = secondHarness.browserManager
        installer.installOrUpdateIfNeeded()

        let updatedSubmenu = try XCTUnwrap(historyItem.submenu as? SumiHistoryMenu)
        XCTAssertTrue(updatedSubmenu === originalSubmenu)
        XCTAssertTrue(updatedSubmenu.browserManager === secondHarness.browserManager)
        XCTAssertEqual(mainMenu.items.filter { $0.title == "History" }.count, 1)
    }

    func testInstallerRemovesSwiftUIHistoryPlaceholderDuplicates() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let mainMenu = NSMenu(title: "Main")
        let placeholder = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        placeholder.submenu = makeSwiftUIHistoryPlaceholderMenu()
        let existingAppKitItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        existingAppKitItem.submenu = SumiHistoryMenu(
            browserManager: nil,
            shortcutManager: nil,
            actionTarget: nil
        )

        mainMenu.addItem(NSMenuItem(title: "File", action: nil, keyEquivalent: ""))
        mainMenu.addItem(placeholder)
        mainMenu.addItem(existingAppKitItem)
        mainMenu.addItem(NSMenuItem(title: "Window", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = mainMenu

        let installer = SumiHistoryMenuInstaller()
        installer.installOrUpdateIfNeeded()

        let historyItems = mainMenu.items.filter { $0.title == "History" }
        XCTAssertEqual(historyItems.count, 1)
        XCTAssertTrue(historyItems.first?.submenu is SumiHistoryMenu)
        XCTAssertFalse(historyItems.first?.submenu === placeholder.submenu)
    }

    func testAppDelegateRefreshRestoresHistoryMenuAfterSwiftUIPlaceholderReplacesIt() async throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let mainMenu = NSMenu(title: "Main")
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        mainMenu.addItem(NSMenuItem(title: "File", action: nil, keyEquivalent: ""))
        mainMenu.addItem(historyItem)
        mainMenu.addItem(NSMenuItem(title: "Window", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = mainMenu

        let harness = try makeHarness()
        let appDelegate = AppDelegate()
        appDelegate.updateHandler = harness.browserManager
        appDelegate.refreshHistoryMenu()
        await drainMainQueue()

        XCTAssertTrue(historyItem.submenu is SumiHistoryMenu)

        historyItem.submenu = makeSwiftUIHistoryPlaceholderMenu()
        XCTAssertFalse(historyItem.submenu is SumiHistoryMenu)

        appDelegate.refreshHistoryMenu()
        await drainMainQueue()

        let restoredMenu = try XCTUnwrap(historyItem.submenu as? SumiHistoryMenu)
        XCTAssertTrue(restoredMenu.browserManager === harness.browserManager)
    }

    func testAppDelegateRefreshDoesNotDuplicateHistoryTopLevelItem() async throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let mainMenu = NSMenu(title: "Main")
        mainMenu.addItem(NSMenuItem(title: "File", action: nil, keyEquivalent: ""))
        mainMenu.addItem(NSMenuItem(title: "Window", action: nil, keyEquivalent: ""))
        mainMenu.addItem(NSMenuItem(title: "Extensions", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = mainMenu

        let appDelegate = AppDelegate()
        appDelegate.refreshHistoryMenu()
        appDelegate.refreshHistoryMenu()
        await drainMainQueue()

        appDelegate.refreshHistoryMenu()
        await drainMainQueue()

        XCTAssertEqual(mainMenu.items.filter { $0.title == "History" }.count, 1)
        XCTAssertTrue(mainMenu.items.first(where: { $0.title == "History" })?.submenu is SumiHistoryMenu)
    }

    private func makeHarness() throws -> (
        browserManager: BrowserManager,
        windowRegistry: WindowRegistry,
        windowState: BrowserWindowState,
        space: Space,
        profile: Profile
    ) {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.modelContext = context
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.historyManager = HistoryManager(context: context, profileId: profile.id)
        browserManager.recentlyClosedManager = RecentlyClosedManager()
        browserManager.lastSessionWindowsStore = LastSessionWindowsStore()
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (browserManager, windowRegistry, windowState, space, profile)
    }

    private func cacheFavicon(for url: URL) {
        guard let cacheKey = SumiFaviconResolver.cacheKey(for: url) else {
            XCTFail("Missing favicon cache key for \(url.absoluteString)")
            return
        }

        let image = NSImage(size: NSSize(width: 16, height: 16))
        image.lockFocus()
        NSColor.systemOrange.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: 16, height: 16)).fill()
        image.unlockFocus()
        TabFaviconStore.cacheImage(image, for: cacheKey)
    }

    private func makeSwiftUIHistoryPlaceholderMenu() -> NSMenu {
        let menu = NSMenu(title: "History")
        menu.addItem(NSMenuItem(title: "Show All History", action: nil, keyEquivalent: ""))
        menu.addItem(NSMenuItem.separator())
        menu.addItem(NSMenuItem(title: "Clear All History", action: nil, keyEquivalent: ""))
        return menu
    }

    private func drainMainQueue() async {
        await withCheckedContinuation { continuation in
            DispatchQueue.main.async {
                continuation.resume()
            }
        }
    }
}
