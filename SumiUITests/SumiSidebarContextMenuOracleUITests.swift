import Foundation
import XCTest

/// Hermetic lifecycle oracle for the visible sidebar context menu. The menu
/// must be dismissible and reopenable on the same stable space surface.
@MainActor
final class SumiSidebarContextMenuOracleUITests: SumiLaunchSmokeUITestCase {
    func testVisibleSidebarContextMenuCanBeDismissedAndReopened() throws {
        let app = try launchApp(
            preferencesHomeURL: try prepareSmokePreferencesHome(),
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5), "The browser window did not appear")

        let spaceIcon = firstSpaceIcon(in: app)
        XCTAssertTrue(spaceIcon.waitForExistence(timeout: 5), "The sidebar space surface is missing")

        openSpaceMenu(on: spaceIcon, in: app)
        window.typeKey(.escape, modifierFlags: [])
        waitForSpaceMenu(toExist: false, in: app)

        openSpaceMenu(on: spaceIcon, in: app)
    }

    private func openSpaceMenu(on spaceIcon: XCUIElement, in app: XCUIApplication) {
        spaceIcon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        waitForSpaceMenu(toExist: true, in: app)
    }

    private func waitForSpaceMenu(toExist: Bool, in app: XCUIApplication) {
        let menuItem = app.menuItems["Edit"]
        let predicate = NSPredicate(
            format: toExist
                ? "exists == true AND hittable == true"
                : "exists == false OR hittable == false"
        )
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: menuItem)
        let result = XCTWaiter().wait(for: [expectation], timeout: 5)
        XCTAssertEqual(
            result,
            .completed,
            toExist ? "The sidebar context menu did not open" : "The sidebar context menu did not dismiss"
        )
    }
}
