import AppKit
import XCTest

@testable import Sumi

@MainActor
final class KeyboardTransientScopeTests: XCTestCase {
    func testFindFieldEscapeUsesFocusedTextCommand() throws {
        let viewController = FindInPageViewController.create()
        viewController.loadView()
        let delegate = FindDelegateProbe()
        viewController.delegate = delegate
        let editor = NSTextView()

        XCTAssertTrue(
            viewController.control(
                try XCTUnwrap(viewController.textField),
                textView: editor,
                doCommandBy: #selector(NSResponder.cancelOperation(_:))
            )
        )
        XCTAssertEqual(delegate.doneCount, 1)
    }

    func testShortcutRecorderOwnsOnlyItsFocusedCaptureLifetime() {
        let root = NSView()
        let priorField = KeyboardTestResponderView()
        let captureView = ShortcutRecorderCaptureView()
        root.addSubview(priorField)
        root.addSubview(captureView)
        let window = NSWindow(contentViewController: NSViewController())
        window.contentView = root
        XCTAssertTrue(window.makeFirstResponder(priorField))
        let focusReturnTarget = window.firstResponder
        var blurCount = 0
        captureView.onBlur = { blurCount += 1 }

        captureView.beginCaptureIfPossible()
        XCTAssertIdentical(window.firstResponder, captureView)

        captureView.endCaptureAndRestoreFocus()
        XCTAssertIdentical(window.firstResponder, focusReturnTarget)
        XCTAssertEqual(blurCount, 0)
    }

    func testShortcutRecorderEndsCaptureWhenItsWindowResignsKey() async {
        let root = NSView()
        let priorField = KeyboardTestResponderView()
        let captureView = ShortcutRecorderCaptureView()
        root.addSubview(priorField)
        root.addSubview(captureView)
        let window = NSWindow(contentViewController: NSViewController())
        window.contentView = root
        XCTAssertTrue(window.makeFirstResponder(priorField))
        var blurCount = 0
        captureView.onBlur = {
            blurCount += 1
            captureView.endCaptureAndRestoreFocus()
        }

        captureView.beginCaptureIfPossible()
        NotificationCenter.default.post(
            name: NSWindow.didResignKeyNotification,
            object: window
        )
        await Task.yield()

        XCTAssertEqual(blurCount, 1)
        XCTAssertIdentical(window.firstResponder, priorField)
    }

    func testShortcutRecorderCapturesKeyEquivalentBeforeMenus() throws {
        let captureView = ShortcutRecorderCaptureView()
        let window = NSWindow(contentViewController: NSViewController())
        window.contentView = captureView
        XCTAssertTrue(window.makeFirstResponder(captureView))
        var capturedCount = 0
        captureView.onKeyDown = { _ in
            capturedCount += 1
            return true
        }
        let event = try XCTUnwrap(
            NSEvent.keyEvent(
                with: .keyDown,
                location: .zero,
                modifierFlags: [.command],
                timestamp: ProcessInfo.processInfo.systemUptime,
                windowNumber: window.windowNumber,
                context: nil,
                characters: "t",
                charactersIgnoringModifiers: "t",
                isARepeat: false,
                keyCode: 0x11
            )
        )

        XCTAssertTrue(captureView.performKeyEquivalent(with: event))
        XCTAssertEqual(capturedCount, 1)
    }
}

private final class KeyboardTestResponderView: NSView {
    override var acceptsFirstResponder: Bool { true }
}

@MainActor
private final class FindDelegateProbe: FindInPageDelegate {
    private(set) var doneCount = 0

    func findInPageNext(_: Any) {
        // Intentionally empty.
    }

    func findInPagePrevious(_: Any) {
        // Intentionally empty.
    }

    func findInPageDone(_: Any) { doneCount += 1 }
}
