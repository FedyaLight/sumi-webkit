import AppKit
import XCTest

@testable import Sumi

@MainActor
final class HoverSidebarManagerTests: XCTestCase {
    func testRefreshMonitoringInstallsAndRemovesMonitorsForActiveCollapsedWindow() async {
        let recorder = EventMonitorRecorder()
        let manager = HoverSidebarManager(
            eventMonitors: recorder.client,
            mouseLocationProvider: { .zero }
        )
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState()

        windowState.tabManager = browserManager.tabManager
        windowState.window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 800, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        windowState.isSidebarVisible = false

        browserManager.windowRegistry = windowRegistry
        manager.windowRegistry = windowRegistry
        manager.attach(browserManager: browserManager, windowState: windowState)

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        manager.start()
        await Task.yield()

        XCTAssertEqual(
            recorder.localMasks,
            [[.mouseMoved, .leftMouseDragged, .rightMouseDragged]]
        )
        XCTAssertEqual(recorder.globalMasks, [[.mouseMoved]])

        windowState.isSidebarVisible = true
        manager.refreshMonitoring()

        XCTAssertEqual(recorder.removedMonitorCount, 2)
    }

    func testRefreshMonitoringDoesNotInstallMonitorsForInactiveWindow() async {
        let recorder = EventMonitorRecorder()
        let manager = HoverSidebarManager(
            eventMonitors: recorder.client,
            mouseLocationProvider: { .zero }
        )
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let hostedWindow = BrowserWindowState()
        let otherWindow = BrowserWindowState()

        hostedWindow.tabManager = browserManager.tabManager
        hostedWindow.isSidebarVisible = false
        otherWindow.tabManager = browserManager.tabManager
        otherWindow.isSidebarVisible = false

        browserManager.windowRegistry = windowRegistry
        manager.windowRegistry = windowRegistry
        manager.attach(browserManager: browserManager, windowState: hostedWindow)

        windowRegistry.register(hostedWindow)
        windowRegistry.register(otherWindow)
        windowRegistry.setActive(otherWindow)

        manager.start()
        await Task.yield()

        XCTAssertTrue(recorder.localMasks.isEmpty)
        XCTAssertTrue(recorder.globalMasks.isEmpty)
        XCTAssertEqual(recorder.removedMonitorCount, 0)
    }
}

@MainActor
private final class EventMonitorRecorder {
    private(set) var localMasks: [NSEvent.EventTypeMask] = []
    private(set) var globalMasks: [NSEvent.EventTypeMask] = []
    private(set) var removedMonitorCount = 0

    var client: HoverSidebarEventMonitorClient {
        HoverSidebarEventMonitorClient(
            addLocalMonitor: { [weak self] mask, _ in
                self?.localMasks.append(mask)
                return NSObject()
            },
            addGlobalMonitor: { [weak self] mask, _ in
                self?.globalMasks.append(mask)
                return NSObject()
            },
            removeMonitor: { [weak self] _ in
                self?.removedMonitorCount += 1
            }
        )
    }
}
