@testable import Sumi
import XCTest

final class ExtensionActionVisibilityTests: XCTestCase {
    func testNoActionsAreHidden() {
        XCTAssertEqual(
            ExtensionActionPlacement.resolve(totalActions: 0),
            .hidden
        )
    }

    func testOneActionStaysInURLBar() {
        XCTAssertEqual(
            ExtensionActionPlacement.resolve(totalActions: 1),
            .urlBar
        )
    }

    func testTwoActionsStayInURLBar() {
        XCTAssertEqual(
            ExtensionActionPlacement.resolve(totalActions: 2),
            .urlBar
        )
    }

    func testThreeActionsMoveToSidebarGrid() {
        XCTAssertEqual(
            ExtensionActionPlacement.resolve(totalActions: 3),
            .sidebarGrid
        )
    }

    func testMoreThanThreeActionsMoveToSidebarGrid() {
        XCTAssertEqual(
            ExtensionActionPlacement.resolve(totalActions: 5),
            .sidebarGrid
        )
    }

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
