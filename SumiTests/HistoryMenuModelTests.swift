import XCTest

@testable import Sumi

@MainActor
final class HistoryMenuModelTests: XCTestCase {
    func testNavigationHistoryButtonMenuOrderingMatchesDDG() {
        let current = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/current"),
            title: "Current",
            isCurrent: true
        )
        let oldestBack = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/oldest"),
            title: "Oldest Back",
            isCurrent: false
        )
        let middleBack = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/middle"),
            title: "Middle Back",
            isCurrent: false
        )
        let newestBack = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/newest"),
            title: "Newest Back",
            isCurrent: false
        )
        let nextForward = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/next"),
            title: "Next Forward",
            isCurrent: false
        )
        let laterForward = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/later"),
            title: "Later Forward",
            isCurrent: false
        )

        let backOrder = SumiNavigationHistoryMenuModel.orderedItems(
            current: current,
            backItems: [oldestBack, middleBack, newestBack],
            forwardItems: [nextForward, laterForward],
            direction: .back
        )
        XCTAssertEqual(backOrder.map(\.title), ["Current", "Newest Back", "Middle Back", "Oldest Back"])
        XCTAssertTrue(backOrder[0].isCurrent)

        let forwardOrder = SumiNavigationHistoryMenuModel.orderedItems(
            current: current,
            backItems: [oldestBack, middleBack, newestBack],
            forwardItems: [nextForward, laterForward],
            direction: .forward
        )
        XCTAssertEqual(forwardOrder.map(\.title), ["Current", "Next Forward", "Later Forward"])
        XCTAssertTrue(forwardOrder[0].isCurrent)
    }
}
