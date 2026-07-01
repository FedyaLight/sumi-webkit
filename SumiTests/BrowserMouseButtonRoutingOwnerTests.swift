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
