import XCTest

@testable import Sumi

@MainActor
final class BrowserApplicationReopenPolicyTests: XCTestCase {
    func testDockReopenCreatesWindowOnlyWhenNoBrowserWindowExists() {
        XCTAssertTrue(
            BrowserApplicationReopenPolicy.shouldCreateNewWindow(
                hasVisibleWindows: false,
                hasOpenBrowserWindows: false
            )
        )
    }

    func testDockReopenUsesAppKitDefaultWhenAWindowIsVisible() {
        XCTAssertFalse(
            BrowserApplicationReopenPolicy.shouldCreateNewWindow(
                hasVisibleWindows: true,
                hasOpenBrowserWindows: false
            )
        )
    }

    func testDockReopenUsesAppKitDefaultForAnExistingMiniaturizedWindow() {
        XCTAssertFalse(
            BrowserApplicationReopenPolicy.shouldCreateNewWindow(
                hasVisibleWindows: false,
                hasOpenBrowserWindows: true
            )
        )
    }
}
