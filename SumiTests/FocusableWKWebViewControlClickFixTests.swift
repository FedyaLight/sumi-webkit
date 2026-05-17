import AppKit
import XCTest
@testable import Sumi

@MainActor
final class FocusableWKWebViewControlClickFixTests: XCTestCase {
    func testImmediateGlanceUsesHoveredLinkForOptionMouseDown() throws {
        let tab = Tab(
            url: URL(string: "https://source.example/page")!,
            name: "Source"
        )
        tab.updateHoveredLink("https://destination.example/page")

        let event = try Self.mouseEvent(modifierFlags: .option)

        XCTAssertEqual(
            tab.immediateGlanceURLForWebViewMouseDown(event),
            URL(string: "https://destination.example/page")
        )
    }

    func testImmediateGlanceRejectsCombinedOptionGesture() throws {
        let tab = Tab(
            url: URL(string: "https://source.example/page")!,
            name: "Source"
        )
        tab.updateHoveredLink("https://destination.example/page")

        let event = try Self.mouseEvent(modifierFlags: [.option, .command])

        XCTAssertNil(tab.immediateGlanceURLForWebViewMouseDown(event))
    }

    func testImmediateDynamicGlanceRequiresEssentialExternalCleanClick() throws {
        let tab = Tab(
            url: URL(string: "https://source.example/page")!,
            name: "Source"
        )
        tab.updateHoveredLink("https://destination.example/page")

        let cleanClick = try Self.mouseEvent(modifierFlags: [])
        XCTAssertNil(tab.immediateGlanceURLForWebViewMouseDown(cleanClick))

        tab.isPinned = true
        XCTAssertEqual(
            tab.immediateGlanceURLForWebViewMouseDown(cleanClick),
            URL(string: "https://destination.example/page")
        )

        tab.updateHoveredLink("https://source.example/other")
        XCTAssertNil(tab.immediateGlanceURLForWebViewMouseDown(cleanClick))
    }

    func testImmediateGlanceRejectsNonPreviewableHoveredLink() throws {
        let tab = Tab(
            url: URL(string: "https://source.example/page")!,
            name: "Source"
        )
        tab.updateHoveredLink("javascript:void(0)")

        let event = try Self.mouseEvent(modifierFlags: .option)

        XCTAssertNil(tab.immediateGlanceURLForWebViewMouseDown(event))
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

    func testRightMouseDownOverrideDoesNotContainControlClickFixMechanism() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let source = try String(
            contentsOf: repositoryRoot.appendingPathComponent(
                "Sumi/Utils/WebKit/FocusableWKWebView.swift"
            ),
            encoding: .utf8
        )
        let marker = "override func rightMouseDown(with event: NSEvent)"
        let start = try XCTUnwrap(source.range(of: marker)).upperBound
        let suffix = source[start...]
        guard let nextOverride = suffix.range(of: "\n    override ") else {
            XCTFail("Could not find override following rightMouseDown")
            return
        }
        let block = String(suffix[..<nextOverride.lowerBound])

        XCTAssertFalse(block.contains("flagsChanged"), "rightMouseDown must not implement control-click flagsChanged synthesis")
        XCTAssertFalse(block.contains("kVK_Control"))
        XCTAssertFalse(block.contains("sendEvent"))
        XCTAssertFalse(block.contains("performDefaultMouseDownBehavior"))
        XCTAssertTrue(block.contains("super.rightMouseDown(with: event)"))
        XCTAssertTrue(block.contains("owningTab?.activate()"))
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
