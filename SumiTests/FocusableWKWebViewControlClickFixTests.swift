import AppKit
@testable import Sumi
import WebKit
import XCTest

@MainActor
final class FocusableWKWebViewControlClickFixTests: XCTestCase {
    func testControlLeftMouseDownAllowlistedHostPassesGateWhenFixEnabled() throws {
        let event = try Self.mouseEvent(modifierFlags: .control)
        XCTAssertTrue(
            FocusableWKWebView.shouldApplyControlClickFix(
                event: event,
                pageHost: "drive.google.com",
                isFixEnabled: true
            )
        )
    }

    func testNonAllowlistedDomainDoesNotPassGate() throws {
        let event = try Self.mouseEvent(modifierFlags: .control)
        XCTAssertFalse(
            FocusableWKWebView.shouldApplyControlClickFix(
                event: event,
                pageHost: "example.com",
                isFixEnabled: true
            )
        )
    }

    func testNonControlLeftMouseDownDoesNotPassGate() throws {
        let event = try Self.mouseEvent(modifierFlags: [])
        XCTAssertFalse(
            FocusableWKWebView.shouldApplyControlClickFix(
                event: event,
                pageHost: "drive.google.com",
                isFixEnabled: true
            )
        )
    }

    func testKillSwitchDisablesGate() throws {
        let event = try Self.mouseEvent(modifierFlags: .control)
        XCTAssertFalse(
            FocusableWKWebView.shouldApplyControlClickFix(
                event: event,
                pageHost: "drive.google.com",
                isFixEnabled: false
            )
        )
    }

    private static func mouseEvent(modifierFlags: NSEvent.ModifierFlags) throws -> NSEvent {
        try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: modifierFlags,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
    }

    private func makeWebView(for tab: Tab) -> FocusableWKWebView {
        let webView = FocusableWKWebView(
            frame: .zero,
            configuration: WKWebViewConfiguration()
        )
        webView.owningTab = tab
        return webView
    }
}
