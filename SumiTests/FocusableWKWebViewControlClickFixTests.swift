import AppKit
import XCTest
@testable import Sumi

@MainActor
final class FocusableWKWebViewControlClickFixTests: XCTestCase {
    func testControlLeftMouseDownAllowlistedHostPassesGateWhenFixEnabled() throws {
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: .control,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        XCTAssertTrue(
            FocusableWKWebView.shouldApplyControlClickFix(
                event: event,
                pageHost: "drive.google.com",
                isFixEnabled: true
            )
        )
    }

    func testNonAllowlistedDomainDoesNotPassGate() throws {
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: .control,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        XCTAssertFalse(
            FocusableWKWebView.shouldApplyControlClickFix(
                event: event,
                pageHost: "example.com",
                isFixEnabled: true
            )
        )
    }

    func testNonControlLeftMouseDownDoesNotPassGate() throws {
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: [],
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
        XCTAssertFalse(
            FocusableWKWebView.shouldApplyControlClickFix(
                event: event,
                pageHost: "drive.google.com",
                isFixEnabled: true
            )
        )
    }

    func testKillSwitchDisablesGate() throws {
        let event = try XCTUnwrap(
            NSEvent.mouseEvent(
                with: .leftMouseDown,
                location: .zero,
                modifierFlags: .control,
                timestamp: 0,
                windowNumber: 0,
                context: nil,
                eventNumber: 0,
                clickCount: 1,
                pressure: 1
            )
        )
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
}
