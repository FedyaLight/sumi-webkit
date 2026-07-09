import AppKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserMenuCloseRoutingOwnerTests: XCTestCase {
    func testCloseCurrentTabUsesKeyWindowStateInsteadOfActiveWindow() {
        let owner = BrowserMenuCloseRoutingOwner()
        let registry = WindowRegistry()
        let keyWindowState = makeWindowState(in: registry)
        let activeWindowState = makeWindowState(in: registry)
        registry.setActive(activeWindowState)

        var closedWindowIds: [UUID] = []
        owner.closeCurrentTab(
            keyWindow: registry.appKitWindow(for: keyWindowState),
            sender: nil,
            windowRegistry: registry,
            closeCurrentTab: { windowState in
                closedWindowIds.append(windowState.id)
            }
        )

        XCTAssertEqual(closedWindowIds, [keyWindowState.id])
    }

    func testCloseWindowUsesKeyWindowStateInsteadOfActiveWindow() {
        let owner = BrowserMenuCloseRoutingOwner()
        let registry = WindowRegistry()
        let keyWindowState = makeWindowState(in: registry)
        let activeWindowState = makeWindowState(in: registry)
        registry.setActive(activeWindowState)

        var closedWindowIds: [UUID] = []
        owner.closeWindow(
            keyWindow: registry.appKitWindow(for: keyWindowState),
            sender: nil,
            windowRegistry: registry,
            closeWindow: { windowState in
                closedWindowIds.append(windowState.id)
            }
        )

        XCTAssertEqual(closedWindowIds, [keyWindowState.id])
    }

    func testCloseCurrentTabFallsBackToActiveWindowWhenNoKeyWindowExists() {
        let owner = BrowserMenuCloseRoutingOwner()
        let registry = WindowRegistry()
        let activeWindowState = makeWindowState(in: registry)
        registry.setActive(activeWindowState)

        var closedWindowIds: [UUID] = []
        owner.closeCurrentTab(
            keyWindow: nil,
            sender: nil,
            windowRegistry: registry,
            closeCurrentTab: { windowState in
                closedWindowIds.append(windowState.id)
            }
        )

        XCTAssertEqual(closedWindowIds, [activeWindowState.id])
    }

    func testCloseWindowLetsChildWindowHandleClose() {
        let owner = BrowserMenuCloseRoutingOwner()
        let registry = WindowRegistry()
        let parentWindowState = makeWindowState(in: registry)
        let childWindow = CloseRecordingWindow(
            contentRect: NSRect(x: 0, y: 0, width: 120, height: 80),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        registry.appKitWindow(for: parentWindowState)?.addChildWindow(childWindow, ordered: .above)
        registry.setActive(parentWindowState)

        var closedWindowIds: [UUID] = []
        owner.closeWindow(
            keyWindow: childWindow,
            sender: nil,
            windowRegistry: registry,
            closeWindow: { windowState in
                closedWindowIds.append(windowState.id)
            }
        )

        XCTAssertTrue(closedWindowIds.isEmpty)
        XCTAssertEqual(childWindow.performCloseCount, 1)
    }

    private func makeWindowState(in registry: WindowRegistry) -> BrowserWindowState {
        let windowState = BrowserWindowState()
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        registry.register(windowState)
        registry.bindAppKitWindow(window, to: windowState)
        return windowState
    }
}

private final class CloseRecordingWindow: NSWindow {
    private(set) var performCloseCount = 0

    override func performClose(_ sender: Any?) {
        performCloseCount += 1
        _ = sender
    }
}
