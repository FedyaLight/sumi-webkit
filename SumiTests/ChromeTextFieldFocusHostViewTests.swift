import AppKit
@testable import Sumi
import XCTest

@MainActor
final class ChromeTextFieldFocusHostViewTests: XCTestCase {
    func testFocusRequestPersistsUntilHostIsAttachedToWindow() {
        let textField = NSTextField()
        let host = ChromeTextFieldFocusHostView(textField: textField)

        host.requestFocus(id: 1, selectAll: false)
        let window = makeKeyTestWindow(contentView: host)

        XCTAssertTrue(host.ownsTextFocus)
        XCTAssertTrue(
            window.firstResponder === textField
                || window.firstResponder === textField.currentEditor()
        )
    }

    func testNewGenerationRefocusesFieldButDuplicateGenerationDoesNot() {
        let textField = NSTextField()
        let host = ChromeTextFieldFocusHostView(textField: textField)
        let otherField = NSTextField()
        let contentView = NSView()
        contentView.addSubview(host)
        contentView.addSubview(otherField)
        let window = makeKeyTestWindow(contentView: contentView)

        host.requestFocus(id: 1, selectAll: false)
        XCTAssertTrue(host.ownsTextFocus)

        XCTAssertTrue(window.makeFirstResponder(otherField))
        host.requestFocus(id: 1, selectAll: false)
        XCTAssertFalse(host.ownsTextFocus)

        host.requestFocus(id: 2, selectAll: false)
        XCTAssertTrue(host.ownsTextFocus)
    }

    func testCancelledRequestDoesNotFocusAfterAttachment() {
        let textField = NSTextField()
        let host = ChromeTextFieldFocusHostView(textField: textField)

        host.requestFocus(id: 1, selectAll: false)
        host.cancelPendingFocus()
        _ = makeKeyTestWindow(contentView: host)

        XCTAssertFalse(host.ownsTextFocus)
    }

    private func makeKeyTestWindow(contentView: NSView) -> NSWindow {
        let window = AlwaysKeyTestWindow(
            contentRect: NSRect(x: 0, y: 0, width: 500, height: 300),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.contentView = contentView
        return window
    }
}

private final class AlwaysKeyTestWindow: NSWindow {
    override var isKeyWindow: Bool { true }
}
