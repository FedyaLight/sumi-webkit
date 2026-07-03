import AppKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserMouseButtonRoutingOwnerTests: XCTestCase {
    func testSideBackButtonTargetsEventWindowInsteadOfActiveWindow() {
        let owner = BrowserMouseButtonRoutingOwner()
        let registry = WindowRegistry()
        let activeWindowState = BrowserWindowState()
        let eventWindowState = BrowserWindowState()
        activeWindowState.window = NSWindow()
        eventWindowState.window = NSWindow()
        registry.register(activeWindowState)
        registry.register(eventWindowState)
        registry.setActive(activeWindowState)
        let router = RecordingBrowserCommandRouter()

        XCTAssertTrue(owner.handleMouseButton(
            3,
            eventWindow: eventWindowState.window,
            mouseButtonRouter: router,
            windowRegistry: registry
        ))

        XCTAssertEqual(router.backWindowIDs, [eventWindowState.id])
        XCTAssertTrue(router.forwardWindowIDs.isEmpty)
    }

    func testSideForwardButtonFallsBackToActiveWindowWhenEventHasNoWindow() {
        let owner = BrowserMouseButtonRoutingOwner()
        let registry = WindowRegistry()
        let activeWindowState = BrowserWindowState()
        registry.register(activeWindowState)
        registry.setActive(activeWindowState)
        let router = RecordingBrowserCommandRouter()

        XCTAssertTrue(owner.handleMouseButton(
            4,
            eventWindow: nil,
            mouseButtonRouter: router,
            windowRegistry: registry
        ))

        XCTAssertEqual(router.forwardWindowIDs, [activeWindowState.id])
        XCTAssertTrue(router.backWindowIDs.isEmpty)
    }

    func testSidebarDeferredSideButtonsDoNotRouteHistory() {
        let owner = BrowserMouseButtonRoutingOwner()
        let registry = WindowRegistry()
        let activeWindowState = BrowserWindowState()
        registry.register(activeWindowState)
        registry.setActive(activeWindowState)
        let router = RecordingBrowserCommandRouter()

        XCTAssertFalse(owner.handleMouseButton(
            3,
            eventWindow: nil,
            mouseButtonRouter: router,
            windowRegistry: registry,
            deferWorkspaceNavigationToSidebar: true
        ))
        XCTAssertFalse(owner.handleMouseButton(
            4,
            eventWindow: nil,
            mouseButtonRouter: router,
            windowRegistry: registry,
            deferWorkspaceNavigationToSidebar: true
        ))

        XCTAssertTrue(router.backWindowIDs.isEmpty)
        XCTAssertTrue(router.forwardWindowIDs.isEmpty)
    }

    func testSidebarDeferralDoesNotChangeMiddleMouseButtonRouting() {
        let owner = BrowserMouseButtonRoutingOwner()
        let registry = WindowRegistry()
        let activeWindowState = BrowserWindowState()
        registry.register(activeWindowState)
        registry.setActive(activeWindowState)
        let router = RecordingBrowserCommandRouter()

        XCTAssertTrue(owner.handleMouseButton(
            2,
            eventWindow: nil,
            mouseButtonRouter: router,
            windowRegistry: registry,
            deferWorkspaceNavigationToSidebar: true
        ))

        XCTAssertEqual(router.focusedWindowIDs, [activeWindowState.id])
        XCTAssertTrue(router.backWindowIDs.isEmpty)
        XCTAssertTrue(router.forwardWindowIDs.isEmpty)
    }

    func testSidebarCaptureRegistryMatchesRegisteredVisibleRegionForSideButtonsOnly() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 240, height: 160),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        let sidebarView = NSView(frame: NSRect(x: 0, y: 0, width: 80, height: 160))
        window.contentView?.addSubview(sidebarView)
        SidebarMouseButtonCaptureRegistry.shared.register(sidebarView, isEnabled: true)

        defer {
            SidebarMouseButtonCaptureRegistry.shared.unregister(sidebarView)
        }

        XCTAssertTrue(SidebarMouseButtonCaptureRegistry.shared.containsWorkspaceMouseButtonEvent(
            buttonNumber: 3,
            locationInWindow: CGPoint(x: 20, y: 20),
            in: window
        ))
        XCTAssertTrue(SidebarMouseButtonCaptureRegistry.shared.containsWorkspaceMouseButtonEvent(
            buttonNumber: 4,
            locationInWindow: CGPoint(x: 20, y: 20),
            in: window
        ))
        XCTAssertFalse(SidebarMouseButtonCaptureRegistry.shared.containsWorkspaceMouseButtonEvent(
            buttonNumber: 3,
            locationInWindow: CGPoint(x: 120, y: 20),
            in: window
        ))
        XCTAssertFalse(SidebarMouseButtonCaptureRegistry.shared.containsWorkspaceMouseButtonEvent(
            buttonNumber: 2,
            locationInWindow: CGPoint(x: 20, y: 20),
            in: window
        ))
    }
}

@MainActor
private final class RecordingBrowserCommandRouter: BrowserMouseButtonCommandRouting {
    var focusedWindowIDs: [UUID] = []
    var backWindowIDs: [UUID] = []
    var forwardWindowIDs: [UUID] = []

    func focusFloatingBar(
        in windowState: BrowserWindowState,
        prefill: String,
        navigateCurrentTab: Bool
    ) {
        _ = prefill
        _ = navigateCurrentTab
        focusedWindowIDs.append(windowState.id)
    }

    func goBack(in windowState: BrowserWindowState) {
        backWindowIDs.append(windowState.id)
    }

    func goForward(in windowState: BrowserWindowState) {
        forwardWindowIDs.append(windowState.id)
    }
}
