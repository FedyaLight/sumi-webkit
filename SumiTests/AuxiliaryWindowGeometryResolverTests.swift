//
//  AuxiliaryWindowGeometryResolverTests.swift
//  SumiTests
//

@testable import Sumi
import AppKit
import XCTest

@MainActor
final class AuxiliaryWindowGeometryResolverTests: XCTestCase {
    func testDefaultGeometryUsesCompactFallbackSize() {
        let geometry = AuxiliaryWindowGeometryResolver.resolveDefault(parentWindow: nil)
        XCTAssertEqual(geometry.contentRect.width, 420, accuracy: 0.5)
        XCTAssertEqual(geometry.contentRect.height, 580, accuracy: 0.5)
    }

    func testExtensionFrameNaNFallsBackToDefaultSize() {
        let geometry = AuxiliaryWindowGeometryResolver.resolve(
            extensionFrame: CGRect(
                x: CGFloat.nan,
                y: CGFloat.nan,
                width: CGFloat.nan,
                height: CGFloat.nan
            ),
            parentWindow: nil
        )
        XCTAssertEqual(geometry.contentRect.width, 420, accuracy: 0.5)
        XCTAssertEqual(geometry.contentRect.height, 580, accuracy: 0.5)
    }

    func testGeometryClampsOversizedDimensions() {
        let visible = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let geometry = AuxiliaryWindowGeometryResolver.resolve(
            extensionFrame: CGRect(x: CGFloat.nan, y: CGFloat.nan, width: 5000, height: 4000),
            parentWindow: nil
        )

        XCTAssertLessThanOrEqual(geometry.contentRect.width, visible.width * 0.85 + 1)
        XCTAssertLessThanOrEqual(geometry.contentRect.height, visible.height * 0.85 + 1)
    }

    func testResolveDoesNotMutateParentWindowFrame() {
        let parent = NSWindow(
            contentRect: NSRect(x: 200, y: 180, width: 1280, height: 840),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        let originalFrame = parent.frame

        _ = AuxiliaryWindowGeometryResolver.resolve(
            extensionFrame: CGRect(x: 100, y: 120, width: 420, height: 580),
            parentWindow: parent
        )

        XCTAssertEqual(parent.frame, originalFrame)
    }
}
