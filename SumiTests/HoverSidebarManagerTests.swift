import AppKit
import XCTest

@testable import Sumi

@MainActor
final class HoverSidebarManagerTests: XCTestCase {
    func testVisibilityPolicyUsesLeftSidebarTriggerAndKeepOpenZones() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

        XCTAssertTrue(HoverSidebarVisibilityPolicy.shouldShowOverlay(
            mouse: CGPoint(x: 95, y: 300),
            windowFrame: frame,
            overlayWidth: 250,
            isOverlayVisible: false,
            contextMenuPresented: false,
            sidebarPosition: .left,
            triggerWidth: 6,
            overshootSlack: 12,
            keepOpenHysteresis: 52,
            verticalSlack: 24
        ))
        XCTAssertFalse(HoverSidebarVisibilityPolicy.shouldShowOverlay(
            mouse: CGPoint(x: 895, y: 300),
            windowFrame: frame,
            overlayWidth: 250,
            isOverlayVisible: false,
            contextMenuPresented: false,
            sidebarPosition: .left,
            triggerWidth: 6,
            overshootSlack: 12,
            keepOpenHysteresis: 52,
            verticalSlack: 24
        ))
        XCTAssertTrue(HoverSidebarVisibilityPolicy.shouldShowOverlay(
            mouse: CGPoint(x: 390, y: 300),
            windowFrame: frame,
            overlayWidth: 250,
            isOverlayVisible: true,
            contextMenuPresented: false,
            sidebarPosition: .left,
            triggerWidth: 6,
            overshootSlack: 12,
            keepOpenHysteresis: 52,
            verticalSlack: 24
        ))
    }

    func testVisibilityPolicyUsesRightSidebarTriggerAndKeepOpenZones() {
        let frame = CGRect(x: 100, y: 100, width: 800, height: 600)

        XCTAssertTrue(HoverSidebarVisibilityPolicy.shouldShowOverlay(
            mouse: CGPoint(x: 905, y: 300),
            windowFrame: frame,
            overlayWidth: 250,
            isOverlayVisible: false,
            contextMenuPresented: false,
            sidebarPosition: .right,
            triggerWidth: 6,
            overshootSlack: 12,
            keepOpenHysteresis: 52,
            verticalSlack: 24
        ))
        XCTAssertFalse(HoverSidebarVisibilityPolicy.shouldShowOverlay(
            mouse: CGPoint(x: 105, y: 300),
            windowFrame: frame,
            overlayWidth: 250,
            isOverlayVisible: false,
            contextMenuPresented: false,
            sidebarPosition: .right,
            triggerWidth: 6,
            overshootSlack: 12,
            keepOpenHysteresis: 52,
            verticalSlack: 24
        ))
        XCTAssertTrue(HoverSidebarVisibilityPolicy.shouldShowOverlay(
            mouse: CGPoint(x: 610, y: 300),
            windowFrame: frame,
            overlayWidth: 250,
            isOverlayVisible: true,
            contextMenuPresented: false,
            sidebarPosition: .right,
            triggerWidth: 6,
            overshootSlack: 12,
            keepOpenHysteresis: 52,
            verticalSlack: 24
        ))
    }

    func testOverlayRevealPrewarmsHostBeforePublishingVisibleState() async {
        let manager = HoverSidebarManager()

        manager.requestOverlayReveal(animationDuration: 0)

        XCTAssertTrue(manager.isOverlayHostPrewarmed)
        XCTAssertFalse(manager.isOverlayVisible)

        await drainMainQueue()

        XCTAssertTrue(manager.isOverlayHostPrewarmed)
        XCTAssertTrue(manager.isOverlayVisible)
    }

    func testOverlayHideReleasesPrewarmedHostAfterAnimationDelay() async {
        let manager = HoverSidebarManager()

        manager.requestOverlayReveal(animationDuration: 0)
        await drainMainQueue()
        manager.setOverlayVisibility(false, animationDuration: 0)

        XCTAssertFalse(manager.isOverlayVisible)
        XCTAssertTrue(manager.isOverlayHostPrewarmed)

        await drainMainQueue()

        XCTAssertFalse(manager.isOverlayHostPrewarmed)
    }

    func testOverlayHideCancelsPendingRevealBeforeVisibleStatePublishes() async {
        let manager = HoverSidebarManager()

        manager.requestOverlayReveal(animationDuration: 0)
        manager.setOverlayVisibility(false, animationDuration: 0)

        await drainMainQueue()

        XCTAssertFalse(manager.isOverlayVisible)
        XCTAssertFalse(manager.isOverlayHostPrewarmed)
    }

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
private func drainMainQueue() async {
    await Task.yield()
    await Task.yield()
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
