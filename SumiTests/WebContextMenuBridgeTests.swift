import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Sumi

@MainActor
final class FocusableWKWebViewContextMenuTests: XCTestCase {
    func testWebKitContextMenuEndTrackingClearsTransientMenuSessionAndRestoresDragCapture() {
        let fixture = makeWebContextMenuFixture()
        let menu = NSMenu()

        XCTAssertTrue(fixture.dragView.shouldCaptureInteraction(at: NSPoint(x: 12, y: 12), eventType: .leftMouseDown))

        openWebContextMenu(in: fixture, menu: menu)

        XCTAssertTrue(fixture.windowState.sidebarInteractionState.isContextMenuPresented)
        XCTAssertFalse(fixture.windowState.sidebarInteractionState.allowsSidebarDragSourceHitTesting)
        XCTAssertFalse(fixture.dragView.shouldCaptureInteraction(at: NSPoint(x: 12, y: 12), eventType: .leftMouseDown))

        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        drainMainRunLoop()

        XCTAssertFalse(fixture.windowState.sidebarInteractionState.isContextMenuPresented)
        XCTAssertTrue(fixture.windowState.sidebarInteractionState.allowsSidebarDragSourceHitTesting)
        XCTAssertTrue(fixture.dragView.shouldCaptureInteraction(at: NSPoint(x: 12, y: 12), eventType: .leftMouseDown))
    }

    func testWebKitContextMenuDidCloseAndEndTrackingCleanupIsIdempotent() {
        let fixture = makeWebContextMenuFixture()
        let menu = NSMenu()

        openWebContextMenu(in: fixture, menu: menu)
        let lifecycleDelegate = menu.delegate

        XCTAssertTrue(fixture.windowState.sidebarInteractionState.isContextMenuPresented)

        lifecycleDelegate?.menuDidClose?(menu)
        NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
        drainMainRunLoop()

        XCTAssertFalse(fixture.windowState.sidebarInteractionState.isContextMenuPresented)
        XCTAssertTrue(fixture.windowState.sidebarInteractionState.allowsSidebarDragSourceHitTesting)
        XCTAssertTrue(fixture.dragView.shouldCaptureInteraction(at: NSPoint(x: 12, y: 12), eventType: .leftMouseDown))
    }

    func testRepeatedWebKitContextMenuEndTrackingDoesNotAccumulateStaleSessions() {
        let fixture = makeWebContextMenuFixture()

        for _ in 0..<3 {
            let menu = NSMenu()

            openWebContextMenu(in: fixture, menu: menu)

            XCTAssertTrue(fixture.windowState.sidebarInteractionState.isContextMenuPresented)
            XCTAssertFalse(fixture.dragView.shouldCaptureInteraction(at: NSPoint(x: 12, y: 12), eventType: .leftMouseDown))

            NotificationCenter.default.post(name: NSMenu.didEndTrackingNotification, object: menu)
            drainMainRunLoop()

            XCTAssertFalse(fixture.windowState.sidebarInteractionState.isContextMenuPresented)
            XCTAssertTrue(fixture.windowState.sidebarInteractionState.allowsSidebarDragSourceHitTesting)
            XCTAssertTrue(fixture.dragView.shouldCaptureInteraction(at: NSPoint(x: 12, y: 12), eventType: .leftMouseDown))
        }
    }

    private func makeWebContextMenuFixture() -> (
        browserManager: BrowserManager,
        windowRegistry: WindowRegistry,
        windowState: BrowserWindowState,
        window: NSWindow,
        tab: Sumi.Tab,
        webView: FocusableWKWebView,
        dragView: SidebarInteractiveItemView
    ) {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let windowState = BrowserWindowState()
        browserManager.windowRegistry = windowRegistry

        let tab = Tab(
            name: "Web",
            browserManager: browserManager
        )
        windowState.currentTabId = tab.id

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        windowState.window = window
        windowRegistry.register(windowState)
        windowRegistry.activeWindowId = windowState.id

        let webView = FocusableWKWebView(
            frame: NSRect(x: 0, y: 0, width: 240, height: 180),
            configuration: WKWebViewConfiguration()
        )
        webView.owningTab = tab
        window.contentView?.addSubview(webView)

        let dragView = SidebarInteractiveItemView(frame: NSRect(x: 0, y: 190, width: 80, height: 36))
        dragView.contextMenuController = windowState.sidebarContextMenuController
        dragView.update(
            rootView: AnyView(Color.clear.frame(width: 80, height: 36)),
            configuration: SidebarAppKitItemConfiguration(
                dragSource: SidebarDragSourceConfiguration(
                    item: SumiDragItem(tabId: UUID(), title: "Drag"),
                    sourceZone: .spaceRegular(UUID()),
                    previewKind: .row,
                    isEnabled: true
                )
            )
        )
        window.contentView?.addSubview(dragView)

        return (browserManager, windowRegistry, windowState, window, tab, webView, dragView)
    }

    private func openWebContextMenu(
        in fixture: (
            browserManager: BrowserManager,
            windowRegistry: WindowRegistry,
            windowState: BrowserWindowState,
            window: NSWindow,
            tab: Sumi.Tab,
            webView: FocusableWKWebView,
            dragView: SidebarInteractiveItemView
        ),
        menu: NSMenu
    ) {
        let event = NSEvent.mouseEvent(
            with: .rightMouseDown,
            location: NSPoint(x: 12, y: 12),
            modifierFlags: [],
            timestamp: 0,
            windowNumber: fixture.window.windowNumber,
            context: nil,
            eventNumber: 0,
            clickCount: 1,
            pressure: 0
        )!
        fixture.webView.willOpenMenu(menu, with: event)
    }

    private func drainMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

}
