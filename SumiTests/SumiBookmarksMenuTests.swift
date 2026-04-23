import AppKit
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiBookmarksMenuTests: XCTestCase {
    private var temporaryDirectories: [URL] = []

    override func tearDown() {
        for directory in temporaryDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        temporaryDirectories.removeAll()
        super.tearDown()
    }

    func testInstallerInsertsBookmarksImmediatelyAfterHistory() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let mainMenu = NSMenu(title: "Main")
        mainMenu.addItem(NSMenuItem(title: "File", action: nil, keyEquivalent: ""))
        mainMenu.addItem(NSMenuItem(title: "History", action: nil, keyEquivalent: ""))
        mainMenu.addItem(NSMenuItem(title: "Window", action: nil, keyEquivalent: ""))
        mainMenu.addItem(NSMenuItem(title: "Extensions", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = mainMenu

        let installer = SumiBookmarksMenuInstaller()
        installer.installOrUpdateIfNeeded()

        XCTAssertEqual(mainMenu.items.map(\.title), ["File", "History", "Bookmarks", "Window", "Extensions"])
        XCTAssertTrue(mainMenu.items[2].submenu is SumiBookmarksMenu)
    }

    func testInstallerInsertsBookmarksBeforeExtensionsWhenHistoryIsMissing() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let mainMenu = NSMenu(title: "Main")
        mainMenu.addItem(NSMenuItem(title: "File", action: nil, keyEquivalent: ""))
        mainMenu.addItem(NSMenuItem(title: "Window", action: nil, keyEquivalent: ""))
        mainMenu.addItem(NSMenuItem(title: "Extensions", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = mainMenu

        let installer = SumiBookmarksMenuInstaller()
        installer.installOrUpdateIfNeeded()

        XCTAssertEqual(mainMenu.items.map(\.title), ["File", "Window", "Bookmarks", "Extensions"])
        XCTAssertTrue(mainMenu.items[2].submenu is SumiBookmarksMenu)
    }

    func testInstallerReplacesPlaceholderAndRemovesDuplicateBookmarksMenus() throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let mainMenu = NSMenu(title: "Main")
        let placeholder = NSMenuItem(title: "Bookmarks", action: nil, keyEquivalent: "")
        placeholder.submenu = makeSwiftUIBookmarksPlaceholderMenu()
        let appKitItem = NSMenuItem(title: "Bookmarks", action: nil, keyEquivalent: "")
        appKitItem.submenu = SumiBookmarksMenu(browserManager: nil, actionTarget: nil)

        mainMenu.addItem(NSMenuItem(title: "File", action: nil, keyEquivalent: ""))
        mainMenu.addItem(placeholder)
        mainMenu.addItem(appKitItem)
        mainMenu.addItem(NSMenuItem(title: "Window", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = mainMenu

        let installer = SumiBookmarksMenuInstaller()
        installer.installOrUpdateIfNeeded()

        let bookmarksItems = mainMenu.items.filter { $0.title == "Bookmarks" }
        XCTAssertEqual(bookmarksItems.count, 1)
        XCTAssertTrue(bookmarksItems.first?.submenu is SumiBookmarksMenu)
        XCTAssertFalse(bookmarksItems.first?.submenu === placeholder.submenu)
    }

    func testMenuBuildsBookmarkThisPageAndEmptyState() throws {
        let harness = try makeHarness()
        let actionTarget = NSObject()
        let menu = SumiBookmarksMenu(
            browserManager: harness.browserManager,
            actionTarget: actionTarget
        )
        menu.update()

        let bookmarkThisPageItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Bookmark This Page…" }))
        XCTAssertEqual(bookmarkThisPageItem.action, #selector(AppDelegate.bookmarkThisPageFromMenu(_:)))
        XCTAssertTrue(bookmarkThisPageItem.target === actionTarget)
        XCTAssertTrue(bookmarkThisPageItem.isEnabled)
        XCTAssertEqual(bookmarkThisPageItem.keyEquivalent, "d")
        XCTAssertEqual(bookmarkThisPageItem.keyEquivalentModifierMask, [.command])

        let bookmarkAllTabsItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Bookmark All Tabs…" }))
        XCTAssertEqual(bookmarkAllTabsItem.action, #selector(AppDelegate.bookmarkAllTabsFromMenu(_:)))
        XCTAssertTrue(bookmarkAllTabsItem.target === actionTarget)
        XCTAssertTrue(bookmarkAllTabsItem.isEnabled)
        XCTAssertEqual(bookmarkAllTabsItem.keyEquivalent, "d")
        XCTAssertEqual(bookmarkAllTabsItem.keyEquivalentModifierMask, [.command, .shift])

        let manageItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Manage Bookmarks" }))
        XCTAssertEqual(manageItem.action, #selector(AppDelegate.manageBookmarksFromMenu(_:)))
        XCTAssertEqual(manageItem.keyEquivalent, "b")
        XCTAssertEqual(manageItem.keyEquivalentModifierMask, [.command, .option])

        let importItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Import Bookmarks…" }))
        XCTAssertEqual(importItem.action, #selector(AppDelegate.importBookmarksFromMenu(_:)))
        XCTAssertTrue(importItem.isEnabled)

        let exportItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Export Bookmarks…" }))
        XCTAssertEqual(exportItem.action, #selector(AppDelegate.exportBookmarksFromMenu(_:)))
        XCTAssertFalse(exportItem.isEnabled)

        let emptyItem = try XCTUnwrap(menu.items.first(where: { $0.title == "No Bookmarks" }))
        XCTAssertFalse(emptyItem.isEnabled)
    }

    func testMenuBuildsDynamicBookmarkItemsWithOpenActionAndURL() throws {
        let harness = try makeHarness()
        let actionTarget = NSObject()
        let url = try XCTUnwrap(URL(string: "https://example.com/docs"))
        _ = try harness.browserManager.bookmarkManager.createBookmark(
            url: url,
            title: "Example Docs"
        )

        let menu = SumiBookmarksMenu(
            browserManager: harness.browserManager,
            actionTarget: actionTarget
        )
        menu.update()

        let bookmarkItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Example Docs" }))
        XCTAssertEqual(bookmarkItem.action, #selector(AppDelegate.openBookmarkFromMenu(_:)))
        XCTAssertTrue(bookmarkItem.target === actionTarget)
        XCTAssertEqual(bookmarkItem.representedObject as? URL, url)
        XCTAssertTrue(bookmarkItem.isEnabled)

        let exportItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Export Bookmarks…" }))
        XCTAssertTrue(exportItem.isEnabled)
    }

    func testMenuBuildsDynamicFolderSubmenus() throws {
        let harness = try makeHarness()
        let actionTarget = NSObject()
        let folder = try harness.browserManager.bookmarkManager.createFolder(title: "Docs")
        let url = try XCTUnwrap(URL(string: "https://example.com/reference"))
        _ = try harness.browserManager.bookmarkManager.createBookmark(
            url: url,
            title: "Reference",
            folderID: folder.id
        )

        let menu = SumiBookmarksMenu(
            browserManager: harness.browserManager,
            actionTarget: actionTarget
        )
        menu.update()

        let folderItem = try XCTUnwrap(menu.items.first(where: { $0.title == "Docs" }))
        let submenu = try XCTUnwrap(folderItem.submenu)
        let bookmarkItem = try XCTUnwrap(submenu.items.first(where: { $0.title == "Reference" }))
        XCTAssertEqual(bookmarkItem.action, #selector(AppDelegate.openBookmarkFromMenu(_:)))
        XCTAssertTrue(bookmarkItem.target === actionTarget)
        XCTAssertEqual(bookmarkItem.representedObject as? URL, url)
    }

    func testAppDelegateRefreshRestoresBookmarksMenuAfterPlaceholderReplacement() async throws {
        let previousMainMenu = NSApp.mainMenu
        defer { NSApp.mainMenu = previousMainMenu }

        let mainMenu = NSMenu(title: "Main")
        let historyItem = NSMenuItem(title: "History", action: nil, keyEquivalent: "")
        let bookmarksItem = NSMenuItem(title: "Bookmarks", action: nil, keyEquivalent: "")
        mainMenu.addItem(NSMenuItem(title: "File", action: nil, keyEquivalent: ""))
        mainMenu.addItem(historyItem)
        mainMenu.addItem(bookmarksItem)
        mainMenu.addItem(NSMenuItem(title: "Window", action: nil, keyEquivalent: ""))
        NSApp.mainMenu = mainMenu

        let harness = try makeHarness()
        let appDelegate = AppDelegate()
        appDelegate.updateHandler = harness.browserManager
        appDelegate.refreshHistoryMenu()
        await drainMainQueue()

        XCTAssertTrue(bookmarksItem.submenu is SumiBookmarksMenu)

        bookmarksItem.submenu = makeSwiftUIBookmarksPlaceholderMenu()
        XCTAssertFalse(bookmarksItem.submenu is SumiBookmarksMenu)

        appDelegate.refreshHistoryMenu()
        await drainMainQueue()

        let restoredMenu = try XCTUnwrap(bookmarksItem.submenu as? SumiBookmarksMenu)
        XCTAssertTrue(restoredMenu.browserManager === harness.browserManager)
    }

    func testAppDelegateRefreshDoesNotDuplicateBookmarksTopLevelItem() async throws {
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

        XCTAssertEqual(mainMenu.items.filter { $0.title == "Bookmarks" }.count, 1)
        XCTAssertTrue(mainMenu.items.first(where: { $0.title == "Bookmarks" })?.submenu is SumiBookmarksMenu)
    }

    private func makeHarness() throws -> (
        browserManager: BrowserManager,
        windowRegistry: WindowRegistry,
        windowState: BrowserWindowState,
        space: Space
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
        browserManager.bookmarkManager = makeBookmarkManager()
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        let tab = browserManager.tabManager.createNewTab(
            url: "https://active.example",
            in: space,
            activate: false
        )
        tab.name = "Active"
        windowState.currentTabId = tab.id
        windowState.isShowingEmptyState = false
        windowState.activeTabForSpace[space.id] = tab.id
        space.activeTabId = tab.id

        return (browserManager, windowRegistry, windowState, space)
    }

    private func makeBookmarkManager() -> SumiBookmarkManager {
        let directory = URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            .appendingPathComponent("SumiBookmarksMenuTests-\(UUID().uuidString)", isDirectory: true)
        temporaryDirectories.append(directory)
        return SumiBookmarkManager(
            database: SumiBookmarkDatabase(directory: directory),
            syncFavicons: false
        )
    }

    private func makeSwiftUIBookmarksPlaceholderMenu() -> NSMenu {
        let menu = NSMenu(title: "Bookmarks")
        menu.addItem(NSMenuItem(title: "Bookmark This Page…", action: nil, keyEquivalent: ""))
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
