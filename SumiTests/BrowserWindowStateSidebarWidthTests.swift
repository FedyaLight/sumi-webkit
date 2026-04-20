import XCTest
@testable import Sumi

final class BrowserWindowStateSidebarWidthTests: XCTestCase {
    func testSidebarWidthClampUsesMinimumWidth() {
        XCTAssertEqual(
            BrowserWindowState.clampedSidebarWidth(120),
            240,
            accuracy: 0.0001
        )
    }

    func testSidebarWidthClampUsesMaximumWidth() {
        XCTAssertEqual(
            BrowserWindowState.clampedSidebarWidth(900),
            BrowserWindowState.sidebarMaximumWidth,
            accuracy: 0.0001
        )
    }

    func testSidebarContentWidthUsesSharedPadding() {
        XCTAssertEqual(
            BrowserWindowState.sidebarContentWidth(for: BrowserWindowState.sidebarMinimumWidth),
            224,
            accuracy: 0.0001
        )
    }
}
