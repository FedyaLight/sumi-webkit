@testable import Sumi
import XCTest

final class ExtensionActionPlacementTests: XCTestCase {
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
}
