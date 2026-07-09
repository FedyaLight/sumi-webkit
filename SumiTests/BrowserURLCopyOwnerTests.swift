import AppKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserURLCopyOwnerTests: XCTestCase {
    func testCopyURLCapturesPreviousClipboardPresentsUndoNotificationAndWritesURL() throws {
        let windowState = BrowserWindowState()
        let url = "https://copy.example/page"
        let spy = NotificationPresentingSpy()
        let commands = BrowserURLBarCommands(browserManager: nil, notifications: { spy })
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString("previous clipboard", forType: .string)

        let success = commands.copyURLToPasteboard(url, in: windowState)

        XCTAssertTrue(success)
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), url)
        XCTAssertEqual(spy.presentNotificationCalls.count, 1)
        let notification = try XCTUnwrap(spy.presentNotificationCalls.first?.0)
        XCTAssertEqual(notification.messageKey, "copy-url")
        XCTAssertEqual(notification.duration, 3.0)
        XCTAssertEqual(notification.action?.label, "Undo")
        XCTAssertEqual(spy.presentNotificationCalls.first?.1?.id, windowState.id)

        notification.action?.handler()
        XCTAssertEqual(NSPasteboard.general.string(forType: .string), "previous clipboard")
    }

    func testCopyURLUndoClearsPasteboardWhenPreviousClipboardWasEmpty() throws {
        let windowState = BrowserWindowState()
        let url = "https://copy.example/empty"
        let spy = NotificationPresentingSpy()
        let commands = BrowserURLBarCommands(browserManager: nil, notifications: { spy })
        NSPasteboard.general.clearContents()

        _ = commands.copyURLToPasteboard(url, in: windowState)

        let notification = try XCTUnwrap(spy.presentNotificationCalls.first?.0)
        notification.action?.handler()
        XCTAssertNil(NSPasteboard.general.string(forType: .string))
    }
}
