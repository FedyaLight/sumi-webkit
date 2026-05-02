import AppKit
import SwiftData
import UserScript
import XCTest

@testable import Sumi

@MainActor
final class HistoryMenuTests: XCTestCase {
    func testHistoryMenuBuildsDDGStyleStructureAndRecentVisitIcons() async throws {
        let harness = try makeHarness()
        let url = URL(string: "https://example.com")!
        try await seedFavicon(for: url)

        let baselineRevision = harness.browserManager.historyManager.revision
        _ = harness.browserManager.historyManager.addVisit(
            url: url,
            title: "Example",
            timestamp: Date(),
            tabId: nil,
            profileId: harness.profile.id
        )
        await waitForHistoryRevision(
            manager: harness.browserManager.historyManager,
            beyond: baselineRevision
        )

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

    func testRecentlyClosedSubmenuShowsIconForClosedTab() async throws {
        let harness = try makeHarness()
        let url = URL(string: "https://example.org")!
        try await seedFavicon(for: url)

        let tab = Tab(url: url, name: "Example Org")
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

    func testNavigationHistoryButtonMenuOrderingMatchesDDG() {
        let current = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/current"),
            title: "Current",
            isCurrent: true
        )
        let oldestBack = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/oldest"),
            title: "Oldest Back",
            isCurrent: false
        )
        let middleBack = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/middle"),
            title: "Middle Back",
            isCurrent: false
        )
        let newestBack = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/newest"),
            title: "Newest Back",
            isCurrent: false
        )
        let nextForward = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/next"),
            title: "Next Forward",
            isCurrent: false
        )
        let laterForward = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/later"),
            title: "Later Forward",
            isCurrent: false
        )

        let backOrder = SumiNavigationHistoryMenuModel.orderedItems(
            current: current,
            backItems: [oldestBack, middleBack, newestBack],
            forwardItems: [nextForward, laterForward],
            direction: .back
        )
        XCTAssertEqual(backOrder.map(\.title), ["Current", "Newest Back", "Middle Back", "Oldest Back"])
        XCTAssertTrue(backOrder[0].isCurrent)

        let forwardOrder = SumiNavigationHistoryMenuModel.orderedItems(
            current: current,
            backItems: [oldestBack, middleBack, newestBack],
            forwardItems: [nextForward, laterForward],
            direction: .forward
        )
        XCTAssertEqual(forwardOrder.map(\.title), ["Current", "Next Forward", "Later Forward"])
        XCTAssertTrue(forwardOrder[0].isCurrent)
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

    private func seedFavicon(for url: URL) async throws {
        let data = try XCTUnwrap(Self.makeImageData(color: .systemOrange, size: 16))
        let faviconURL = try XCTUnwrap(URL(string: "https://\(url.host ?? "example.com")/favicon-test.png"))
        try await SumiFaviconSystem.shared.manager.storeFavicon(data, with: faviconURL, for: url)
        let favicon = await SumiFaviconSystem.shared.manager.getCachedFavicon(for: url, sizeCategory: .small, fallBackToSmaller: false)
        XCTAssertNotNil(favicon, "Expected favicon cache to be seeded for \(url.absoluteString)")
    }

    private static func makeDataURL(color: NSColor, size: CGFloat) -> URL? {
        guard let data = makeImageData(color: color, size: size) else { return nil }
        return URL(string: "data:image/png;base64,\(data.base64EncodedString())")
    }

    private static func makeImageData(color: NSColor, size: CGFloat) -> Data? {
        let pixelSize = max(1, Int(size.rounded()))
        guard let bitmap = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: pixelSize,
            pixelsHigh: pixelSize,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ) else {
            return nil
        }

        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: bitmap)
        color.setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixelSize, height: pixelSize)).fill()
        NSGraphicsContext.restoreGraphicsState()

        return bitmap.representation(using: .png, properties: [:])
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

    private func waitForHistoryRevision(
        manager: HistoryManager,
        beyond baseline: UInt
    ) async {
        for _ in 0..<20 {
            if manager.revision > baseline {
                return
            }
            await drainMainQueue()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
