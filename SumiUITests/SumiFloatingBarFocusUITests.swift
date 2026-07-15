import Foundation
import XCTest

@MainActor
final class SumiFloatingBarFocusUITests: SumiLaunchSmokeUITestCase {
    func testCommandTMakesFloatingBarInputKeyboardFocusOwner() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(
            waitForFloatingBar(in: app, timeout: 5),
            "Floating bar did not appear after Cmd+T"
        )

        let input = element(withIdentifier: "floating-bar-input", in: app)
        let focusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: input
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [focusExpectation], timeout: 5),
            .completed,
            "Cmd+T did not make the floating bar input the keyboard focus owner"
        )
    }
}
