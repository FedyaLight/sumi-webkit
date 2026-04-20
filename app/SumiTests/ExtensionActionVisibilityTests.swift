import XCTest
@testable import Sumi

final class ExtensionActionVisibilityTests: XCTestCase {
    func testNoActionsFitWhenWidthIsZero() {
        XCTAssertEqual(
            ExtensionActionVisibility.visibleCount(totalActions: 3, availableWidth: 0),
            0
        )
    }

    func testOneActionFitsAtExactButtonWidth() {
        XCTAssertEqual(
            ExtensionActionVisibility.visibleCount(totalActions: 3, availableWidth: 28),
            1
        )
    }

    func testPartialOverflowKeepsLeadingActionsOnly() {
        XCTAssertEqual(
            ExtensionActionVisibility.visibleCount(totalActions: 5, availableWidth: 92),
            3
        )
    }

    func testWideContainerShowsAllActions() {
        XCTAssertEqual(
            ExtensionActionVisibility.visibleCount(totalActions: 4, availableWidth: 200),
            4
        )
    }
}
