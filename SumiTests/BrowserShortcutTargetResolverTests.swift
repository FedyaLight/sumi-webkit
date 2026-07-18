import AppKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserShortcutTargetResolverTests: XCTestCase {
    func testExactBrowserWindowResolvesBrowserState() {
        let registry = WindowRegistry()
        let state = BrowserWindowState()
        let window = NSWindow()
        registry.register(state)
        registry.bindAppKitWindow(window, to: state)

        guard case .browser(let context) = makeResolver(windows: registry)
            .resolve(keyWindow: window)
        else { return XCTFail("Expected browser window") }
        XCTAssertIdentical(context.windowState, state)
        XCTAssertIdentical(context.appKitWindow, window)
    }

    func testChildWindowRemainsForeignForResponderChain() {
        let registry = WindowRegistry()
        let state = BrowserWindowState()
        let parent = NSWindow()
        let child = NSWindow()
        registry.register(state)
        registry.bindAppKitWindow(parent, to: state)
        parent.addChildWindow(child, ordered: .above)

        guard case .foreignWindow(let resolved) = makeResolver(windows: registry)
            .resolve(keyWindow: child)
        else { return XCTFail("Expected foreign window") }
        XCTAssertIdentical(resolved, child)
    }

    func testMissingKeyWindowResolvesNone() {
        guard case .none = makeResolver(windows: WindowRegistry())
            .resolve(keyWindow: nil)
        else { return XCTFail("Expected no target") }
    }

    private func makeResolver(
        windows: WindowRegistry
    ) -> BrowserShortcutTargetResolver {
        BrowserShortcutTargetResolver(
            windows: windows,
            pages: ActivePageResolver(
                activeWindow: { nil },
                selectedTab: { _ in nil },
                glanceSnapshot: { _ in nil },
                windowOwnedWebView: { _, _ in nil }
            )
        )
    }
}
