import AppKit
@testable import Sumi
import XCTest

@MainActor
final class FocusableWKWebViewControlClickFixTests: XCTestCase {
    func testDynamicGlanceDefersOptionMouseDownToNavigationPolicy() throws {
        let tab = Tab(
            url: URL(string: "https://source.example/page")!,
            name: "Source"
        )
        tab.updateHoveredLink("https://destination.example/page")

        let event = try Self.mouseEvent(modifierFlags: .option)

        XCTAssertNil(tab.dynamicGlanceURLForWebViewMouseDown(event))
    }

    func testDynamicGlanceRejectsCombinedOptionGesture() throws {
        let tab = Tab(
            url: URL(string: "https://source.example/page")!,
            name: "Source"
        )
        tab.updateHoveredLink("https://destination.example/page")

        let event = try Self.mouseEvent(modifierFlags: [.option, .command])

        XCTAssertNil(tab.dynamicGlanceURLForWebViewMouseDown(event))
    }

    func testDynamicGlanceRequiresEssentialExternalCleanClick() throws {
        let tab = Tab(
            url: URL(string: "https://source.example/page")!,
            name: "Source"
        )
        tab.updateHoveredLink("https://destination.example/page")

        let cleanClick = try Self.mouseEvent(modifierFlags: [])
        XCTAssertNil(tab.dynamicGlanceURLForWebViewMouseDown(cleanClick))

        tab.isPinned = true
        XCTAssertEqual(
            tab.dynamicGlanceURLForWebViewMouseDown(cleanClick),
            URL(string: "https://destination.example/page")
        )

        tab.updateHoveredLink("https://source.example/other")
        XCTAssertNil(tab.dynamicGlanceURLForWebViewMouseDown(cleanClick))
    }

    func testDynamicGlanceRejectsNonPreviewableHoveredLink() throws {
        let tab = Tab(
            url: URL(string: "https://source.example/page")!,
            name: "Source"
        )
        tab.updateHoveredLink("javascript:void(0)")

        let event = try Self.mouseEvent(modifierFlags: .option)

        XCTAssertNil(tab.dynamicGlanceURLForWebViewMouseDown(event))
    }

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
}
