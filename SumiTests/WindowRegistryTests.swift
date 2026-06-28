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
}
