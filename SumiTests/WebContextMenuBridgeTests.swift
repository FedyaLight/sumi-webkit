import AppKit
import SwiftUI
import WebKit
import XCTest
@testable import Sumi

@MainActor
final class WebContextMenuBridgeTests: XCTestCase {
    func testInstallingBridgeTwiceOnSharedUserContentControllerDoesNotDuplicateScriptRegistration() {
        let configuration = WKWebViewConfiguration()
        let firstTab = Tab(name: "First")
        let secondTab = Tab(name: "Second")

        let firstBridge = WebContextMenuBridge(
            tab: firstTab,
            configuration: configuration
        )
        XCTAssertEqual(
            configuration.userContentController.userScripts.count,
            1
        )

        let secondBridge = WebContextMenuBridge(
            tab: secondTab,
            configuration: configuration
        )
        XCTAssertEqual(
            configuration.userContentController.userScripts.count,
            1
        )

        _ = firstBridge
        _ = secondBridge
    }

    func testWebKitContextMenuEndTrackingClearsTransientMenuSessionAndRestoresDragCapture() {
        let fixture = makeWebContextMenuFixture()
        let menu = NSMenu()

        XCTAssertTrue(fixture.dragView.shouldCaptureInteraction(at: NSPoint(x: 12, y: 12), eventType: .leftMouseDown))

        fixture.webView.beginContextMenuLifecycleForTesting(on: menu, windowState: fixture.windowState)

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

        fixture.webView.beginContextMenuLifecycleForTesting(on: menu, windowState: fixture.windowState)
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

            fixture.webView.beginContextMenuLifecycleForTesting(on: menu, windowState: fixture.windowState)

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
        windowState: BrowserWindowState,
        window: NSWindow,
        webView: FocusableWKWebView,
        dragView: SidebarInteractiveItemView
    ) {
        let windowState = BrowserWindowState()
        let tab = Tab(name: "Web", skipFaviconFetch: true)

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 480, height: 320),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        windowState.window = window

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

        return (windowState, window, webView, dragView)
    }

    private func drainMainRunLoop() {
        RunLoop.main.run(until: Date().addingTimeInterval(0.02))
    }

}
