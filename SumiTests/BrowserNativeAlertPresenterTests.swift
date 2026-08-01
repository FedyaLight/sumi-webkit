import AppKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserNativeAlertPresenterTests: XCTestCase {
    func testDestructiveConfirmationUsesNativeAlertSemantics() throws {
        let alert = BrowserNativeAlertPresenter.makeDestructiveConfirmationAlert(
            title: "Delete Profile?",
            message: "All profile data will be deleted.",
            confirmButtonTitle: "Delete Profile"
        )

        XCTAssertEqual(alert.alertStyle, .warning)
        XCTAssertEqual(alert.messageText, "Delete Profile?")
        XCTAssertEqual(
            alert.informativeText,
            "All profile data will be deleted."
        )
        XCTAssertTrue(try XCTUnwrap(alert.buttons.first).hasDestructiveAction)
        XCTAssertEqual(try XCTUnwrap(alert.buttons.last).keyEquivalent, "\u{1b}")
    }

    func testNoticeUsesNativeAlertAndKeepsProfileSubtitle() {
        let alert = BrowserNativeAlertPresenter.makeNoticeAlert(
            title: "Profile Deleted",
            subtitle: "Personal",
            message: "Cleanup is pending."
        )

        XCTAssertEqual(alert.alertStyle, .informational)
        XCTAssertEqual(alert.messageText, "Profile Deleted")
        XCTAssertEqual(alert.informativeText, "Personal\n\nCleanup is pending.")
        XCTAssertEqual(alert.buttons.map(\.title), ["OK"])
    }

    func testPreferredSettingsWindowWinsOverActiveBrowserWindow() {
        let settingsWindow = NSWindow()
        let browserWindow = NSWindow()

        let resolvedWindow = BrowserNativeAlertPresenter.resolvePresentationWindow(
            preferredWindow: settingsWindow,
            activeBrowserWindow: browserWindow,
            keyWindow: browserWindow,
            mainWindow: browserWindow
        )

        XCTAssertTrue(resolvedWindow === settingsWindow)
    }
}
