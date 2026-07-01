@testable import Sumi
import XCTest

@MainActor
final class WindowRegistryTests: XCTestCase {
    func testAwaitNextRegisteredWindowReturnsNewWindow() async {
        let registry = WindowRegistry()
        let existingWindow = BrowserWindowState()
        registry.register(existingWindow)

        let awaitedWindowTask = Task { @MainActor in
            await registry.awaitNextRegisteredWindow(
                excluding: [existingWindow.id]
            )
        }

        let newWindow = BrowserWindowState()
        registry.register(newWindow)

        let awaitedWindow = await awaitedWindowTask.value
        XCTAssertEqual(awaitedWindow?.id, newWindow.id)
    }

    func testAwaitNextRegisteredWindowReturnsAlreadyRegisteredWindowWhenAvailable() async {
        let registry = WindowRegistry()
        let firstWindow = BrowserWindowState()
        let secondWindow = BrowserWindowState()
        registry.register(firstWindow)
        registry.register(secondWindow)

        let awaitedWindow = await registry.awaitNextRegisteredWindow(
            excluding: [firstWindow.id]
        )

        XCTAssertEqual(awaitedWindow?.id, secondWindow.id)
    }

    func testAwaitNextRegisteredWindowTimesOutAndDoesNotPoisonFutureAwaiters() async {
        let registry = WindowRegistry()

        let timedOutWindow = await registry.awaitNextRegisteredWindow(
            excluding: [],
            timeoutNanoseconds: 20_000_000
        )

        XCTAssertNil(timedOutWindow)

        let awaitedWindowTask = Task { @MainActor in
            await registry.awaitNextRegisteredWindow(
                excluding: [],
                timeoutNanoseconds: 500_000_000
            )
        }
        let newWindow = BrowserWindowState()
        registry.register(newWindow)

        let awaitedWindow = await awaitedWindowTask.value
        XCTAssertEqual(awaitedWindow?.id, newWindow.id)
    }

    func testUnregisterRunsCloseCallbackOnlyOnceForDuplicateCloseSignals() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        var closedWindowIds: [UUID] = []
        var allWindowsClosedCount = 0

        registry.onWindowClose = { closedWindowIds.append($0) }
        registry.onAllWindowsClosed = { allWindowsClosedCount += 1 }
        registry.register(window)
        registry.setActive(window)

        registry.unregister(window.id)
        registry.unregister(window.id)

        XCTAssertEqual(closedWindowIds, [window.id])
        XCTAssertEqual(allWindowsClosedCount, 1)
        XCTAssertNil(registry.activeWindowId)
        XCTAssertTrue(registry.windows.isEmpty)
    }

    func testUnregisterActiveWindowClearsActiveWithoutPromotingAnotherWindow() {
        let registry = WindowRegistry()
        let closingWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        var activatedWindowIds: [UUID] = []

        registry.register(closingWindow)
        registry.register(survivingWindow)
        registry.setActive(closingWindow)
        registry.onActiveWindowChange = { activatedWindowIds.append($0.id) }

        registry.unregister(closingWindow.id)

        XCTAssertNil(registry.activeWindowId)
        XCTAssertNil(registry.activeWindow)
        XCTAssertTrue(registry.windows.keys.contains(survivingWindow.id))
        XCTAssertTrue(activatedWindowIds.isEmpty)
    }

    func testUnregisterActiveWindowPromotesFocusedRegisteredAppKitWindow() {
        let registry = WindowRegistry()
        let closingWindow = BrowserWindowState()
        let survivingWindow = BrowserWindowState()
        let survivingAppKitWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        var activatedWindowIds: [UUID] = []

        survivingWindow.window = survivingAppKitWindow
        registry.keyAppKitWindowProvider = { survivingAppKitWindow }
        registry.mainAppKitWindowProvider = { nil }
        registry.register(closingWindow)
        registry.register(survivingWindow)
        registry.setActive(closingWindow)
        registry.onActiveWindowChange = { activatedWindowIds.append($0.id) }

        registry.unregister(closingWindow.id)

        XCTAssertEqual(registry.activeWindowId, survivingWindow.id)
        XCTAssertIdentical(registry.activeWindow, survivingWindow)
        XCTAssertEqual(activatedWindowIds, [survivingWindow.id])
    }

    func testSetActiveBeforeRegisterReplacesPreviousActiveWhenRegistered() {
        let registry = WindowRegistry()
        let previousWindow = BrowserWindowState()
        let pendingWindow = BrowserWindowState()
        var activatedWindowIds: [UUID] = []

        registry.register(previousWindow)
        registry.setActive(previousWindow)
        registry.onActiveWindowChange = { activatedWindowIds.append($0.id) }

        registry.setActive(pendingWindow)

        XCTAssertEqual(registry.activeWindowId, pendingWindow.id)
        XCTAssertNil(registry.activeWindow)
        XCTAssertTrue(activatedWindowIds.isEmpty)

        registry.register(pendingWindow)

        XCTAssertEqual(registry.activeWindowId, pendingWindow.id)
        XCTAssertIdentical(registry.activeWindow, pendingWindow)
        XCTAssertEqual(activatedWindowIds, [pendingWindow.id])
    }

    func testSetActiveBeforeRegisterBecomesActiveWhenRegistered() {
        let registry = WindowRegistry()
        let window = BrowserWindowState()
        var activatedWindowIds: [UUID] = []
        registry.onActiveWindowChange = { activatedWindowIds.append($0.id) }

        registry.setActive(window)

        XCTAssertEqual(registry.activeWindowId, window.id)
        XCTAssertNil(registry.activeWindow)
        XCTAssertTrue(activatedWindowIds.isEmpty)

        registry.register(window)

        XCTAssertEqual(registry.activeWindowId, window.id)
        XCTAssertIdentical(registry.activeWindow, window)
        XCTAssertEqual(activatedWindowIds, [window.id])
    }

    func testWindowStateContainingReturnsParentForChildWindow() {
        let registry = WindowRegistry()
        let parentWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 200, height: 120),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let childWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 100, height: 80),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        let windowState = BrowserWindowState()
        windowState.window = parentWindow
        parentWindow.addChildWindow(childWindow, ordered: .above)
        registry.register(windowState)

        XCTAssertIdentical(registry.windowState(containing: childWindow), windowState)
    }
}
