import XCTest

@testable import Sumi

@MainActor
final class BrowserHistoryClearCommandTests: XCTestCase {
    func testExecuteDismissesCollapsedSidebarBeforeConfirmationAndClearsWhenConfirmed() async {
        var events: [String] = []
        let command = BrowserHistoryClearCommand(
            requestCollapsedSidebarDismissal: {
                events.append("dismiss")
            },
            confirmClearAllHistory: {
                events.append("confirm")
                return true
            },
            clearAllHistory: {
                events.append("clear")
            }
        )

        command.execute()
        await Task.yield()

        XCTAssertEqual(events, ["dismiss", "confirm", "clear"])
    }

    func testExecuteDoesNotClearWhenUserCancels() async {
        var events: [String] = []
        let command = BrowserHistoryClearCommand(
            requestCollapsedSidebarDismissal: {
                events.append("dismiss")
            },
            confirmClearAllHistory: {
                events.append("confirm")
                return false
            },
            clearAllHistory: {
                events.append("clear")
            }
        )

        command.execute()
        await Task.yield()

        XCTAssertEqual(events, ["dismiss", "confirm"])
    }
}
