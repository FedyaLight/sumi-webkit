import AppKit
import XCTest

@testable import Sumi

@MainActor
final class HoverSidebarManagerTests: XCTestCase {
    func testOverlayLifecycleUsesExplicitHostStates() async {
        let manager = HoverSidebarManager()

        XCTAssertEqual(manager.overlayHostLifecycleState, .unmounted)

        manager.retainOverlayHostWhileCollapsed()
        XCTAssertEqual(manager.overlayHostLifecycleState, .retainedHidden)

        manager.requestOverlayReveal(animationDuration: 0)
        await drainMainQueue()
        XCTAssertEqual(manager.overlayHostLifecycleState, .visible)

        manager.setOverlayVisibility(false, animationDuration: 0)
        XCTAssertEqual(manager.overlayHostLifecycleState, .retainedHidden)

        manager.releaseOverlayHostForMemoryPressure()
        XCTAssertEqual(manager.overlayHostLifecycleState, .unmounted)
    }

    func testDefaultActivationZoneMatchesZenCompactSidebarEdge() {
        let manager = HoverSidebarManager()

        XCTAssertEqual(manager.triggerWidth, 5)
        XCTAssertEqual(manager.overshootSlack, 10)
        XCTAssertEqual(manager.keepOpenHysteresis, 0)
        XCTAssertEqual(manager.verticalSlack, 7)
    }

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

    func testOverlayHideKeepsPrewarmedHostForCollapsedReuse() async {
        let manager = HoverSidebarManager()

        manager.requestOverlayReveal(animationDuration: 0)
        await drainMainQueue()
        manager.setOverlayVisibility(false, animationDuration: 0)

        XCTAssertFalse(manager.isOverlayVisible)
        XCTAssertTrue(manager.isOverlayHostPrewarmed)

        await drainMainQueue()

        XCTAssertTrue(manager.isOverlayHostPrewarmed)
    }

    func testInactiveCollapsedWindowReleasesPrewarmedHostAfterRetentionDelay() async {
        let recorder = EventMonitorRecorder()
        let manager = HoverSidebarManager(
            eventMonitors: recorder.client,
            mouseLocationProvider: { .zero },
            inactiveHostRetentionDelay: 0.03
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
        manager.attach(runtime: .live(browserManager: browserManager), windowState: hostedWindow)

        windowRegistry.register(hostedWindow)
        windowRegistry.register(otherWindow)
        windowRegistry.setActive(hostedWindow)

        manager.start()
        await waitForPrewarmedHost(manager)

        XCTAssertTrue(manager.isOverlayHostPrewarmed)

        windowRegistry.setActive(otherWindow)
        manager.refreshMonitoring()

        XCTAssertFalse(manager.isOverlayVisible)
        XCTAssertTrue(manager.isOverlayHostPrewarmed)

        await sleep(milliseconds: 60)

        XCTAssertFalse(manager.isOverlayHostPrewarmed)
    }

    func testReactivatingCollapsedWindowCancelsInactiveHostRelease() async {
        let recorder = EventMonitorRecorder()
        let manager = HoverSidebarManager(
            eventMonitors: recorder.client,
            mouseLocationProvider: { .zero },
            inactiveHostRetentionDelay: 0.03
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
        manager.attach(runtime: .live(browserManager: browserManager), windowState: hostedWindow)

        windowRegistry.register(hostedWindow)
        windowRegistry.register(otherWindow)
        windowRegistry.setActive(hostedWindow)

        manager.start()
        await waitForPrewarmedHost(manager)

        XCTAssertTrue(manager.isOverlayHostPrewarmed)

        windowRegistry.setActive(otherWindow)
        manager.refreshMonitoring()
        windowRegistry.setActive(hostedWindow)
        manager.refreshMonitoring()
        await sleep(milliseconds: 60)

        XCTAssertTrue(manager.isOverlayHostPrewarmed)
    }

    func testPinnedInteractionRetainsHost() async {
        let manager = HoverSidebarManager()

        manager.requestOverlayReveal(animationDuration: 0)
        await drainMainQueue()
        manager.setOverlayVisibility(false, animationDuration: 0)
        await drainMainQueue()

        manager.retainOverlayHostForPinnedInteraction()
        await sleep(milliseconds: 60)

        XCTAssertFalse(manager.isOverlayVisible)
        XCTAssertTrue(manager.isOverlayHostPrewarmed)
    }

    func testMemoryPressureReleaseDropsPrewarmedHost() async {
        let manager = HoverSidebarManager()

        manager.requestOverlayReveal(animationDuration: 0)
        await drainMainQueue()

        XCTAssertTrue(manager.isOverlayVisible)
        XCTAssertTrue(manager.isOverlayHostPrewarmed)

        manager.releaseOverlayHostForMemoryPressure()

        XCTAssertFalse(manager.isOverlayVisible)
        XCTAssertFalse(manager.isOverlayHostPrewarmed)
    }

    func testOverlayHideCancelsPendingRevealBeforeVisibleStatePublishes() async {
        let manager = HoverSidebarManager()

        manager.requestOverlayReveal(animationDuration: 0)
        manager.setOverlayVisibility(false, animationDuration: 0)

        await drainMainQueue()

        XCTAssertFalse(manager.isOverlayVisible)
        XCTAssertTrue(manager.isOverlayHostPrewarmed)
    }

    func testPendingPointerRevealDoesNotPublishVisibleAfterPointerLeavesProjectedOverlay() async {
        var mouse = CGPoint(x: 102, y: 300)
        let harness = makePointerRevealHarness(mouseLocationProvider: { mouse })
        defer {
            harness.windowRegistry.unregister(harness.windowState.id)
        }

        harness.manager.requestPointerOverlayReveal(animationDuration: 0)

        XCTAssertTrue(harness.manager.isOverlayHostPrewarmed)
        XCTAssertFalse(harness.manager.isOverlayVisible)

        mouse = CGPoint(x: 650, y: 300)
        await drainMainQueue()

        XCTAssertTrue(harness.manager.isOverlayHostPrewarmed)
        XCTAssertFalse(harness.manager.isOverlayVisible)
    }

    func testPendingPointerRevealPublishesVisibleWhenPointerMovesIntoProjectedOverlay() async {
        var mouse = CGPoint(x: 102, y: 300)
        let harness = makePointerRevealHarness(mouseLocationProvider: { mouse })
        defer {
            harness.windowRegistry.unregister(harness.windowState.id)
        }

        harness.manager.requestPointerOverlayReveal(animationDuration: 0)

        mouse = CGPoint(x: 180, y: 300)
        await drainMainQueue()

        XCTAssertTrue(harness.manager.isOverlayVisible)
        XCTAssertTrue(harness.manager.isOverlayHostPrewarmed)
    }

    func testPendingPointerRevealUsesExplicitRightSidebarPosition() async {
        var mouse = CGPoint(x: 898, y: 300)
        let harness = makePointerRevealHarness(mouseLocationProvider: { mouse })
        defer {
            harness.windowRegistry.unregister(harness.windowState.id)
        }

        harness.manager.sidebarPosition = .left
        harness.manager.requestPointerOverlayReveal(
            animationDuration: 0,
            sidebarPosition: .right
        )

        mouse = CGPoint(x: 820, y: 300)
        await drainMainQueue()

        XCTAssertTrue(harness.manager.isOverlayVisible)
        XCTAssertTrue(harness.manager.isOverlayHostPrewarmed)
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
        manager.attach(runtime: .live(browserManager: browserManager), windowState: windowState)

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        manager.start()
        await waitForPrewarmedHost(manager)

        XCTAssertEqual(
            recorder.localMasks,
            [[.mouseMoved, .leftMouseDragged, .rightMouseDragged]]
        )
        XCTAssertTrue(manager.isOverlayHostPrewarmed)

        windowState.isSidebarVisible = true
        manager.refreshMonitoring()

        XCTAssertEqual(recorder.removedMonitorCount, 1)
        XCTAssertFalse(manager.isOverlayHostPrewarmed)
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
        manager.attach(runtime: .live(browserManager: browserManager), windowState: hostedWindow)

        windowRegistry.register(hostedWindow)
        windowRegistry.register(otherWindow)
        windowRegistry.setActive(otherWindow)

        manager.start()
        await drainMainQueue()

        XCTAssertTrue(recorder.localMasks.isEmpty)
        XCTAssertEqual(recorder.removedMonitorCount, 0)
    }
}

@MainActor
private func drainMainQueue() async {
    await Task.yield()
    await Task.yield()
}

@MainActor
private func waitForPrewarmedHost(_ manager: HoverSidebarManager) async {
    for _ in 0..<10 {
        if manager.isOverlayHostPrewarmed {
            return
        }
        await drainMainQueue()
    }
}

private func sleep(milliseconds: UInt64) async {
    try? await Task.sleep(nanoseconds: milliseconds * 1_000_000)
}

@MainActor
private struct PointerRevealHarness {
    let manager: HoverSidebarManager
    let browserManager: BrowserManager
    let windowRegistry: WindowRegistry
    let windowState: BrowserWindowState
    let recorder: EventMonitorRecorder
}

@MainActor
private func makePointerRevealHarness(
    mouseLocationProvider: @escaping () -> CGPoint
) -> PointerRevealHarness {
    let recorder = EventMonitorRecorder()
    let manager = HoverSidebarManager(
        eventMonitors: recorder.client,
        mouseLocationProvider: mouseLocationProvider,
        inactiveHostRetentionDelay: 0
    )
    let browserManager = BrowserManager()
    let windowRegistry = WindowRegistry()
    let windowState = BrowserWindowState()
    windowState.tabManager = browserManager.tabManager
    windowState.window = NSWindow(
        contentRect: NSRect(x: 100, y: 100, width: 800, height: 600),
        styleMask: [.titled],
        backing: .buffered,
        defer: false
    )
    windowState.isSidebarVisible = false

    browserManager.windowRegistry = windowRegistry
    manager.windowRegistry = windowRegistry
    manager.attach(runtime: .live(browserManager: browserManager), windowState: windowState)

    windowRegistry.register(windowState)
    windowRegistry.setActive(windowState)
    manager.start()
    manager.refreshMonitoring()

    return PointerRevealHarness(
        manager: manager,
        browserManager: browserManager,
        windowRegistry: windowRegistry,
        windowState: windowState,
        recorder: recorder
    )
}

@MainActor
private final class EventMonitorRecorder {
    private(set) var localMasks: [NSEvent.EventTypeMask] = []
    private(set) var removedMonitorCount = 0

    var client: HoverSidebarEventMonitorClient {
        HoverSidebarEventMonitorClient(
            addLocalMonitor: { [weak self] mask, _ in
                self?.localMasks.append(mask)
                return NSObject()
            },
            removeMonitor: { [weak self] _ in
                self?.removedMonitorCount += 1
            }
        )
    }
}
