import Foundation
import XCTest

@MainActor
final class SumiCommandPaletteFocusUITests: SumiLaunchSmokeUITestCase {
    func testCommandTMakesCommandPaletteInputKeyboardFocusOwner() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(
            waitForCommandPalette(in: app, timeout: 5),
            "Command palette did not appear after Cmd+T"
        )

        let input = element(withIdentifier: "command-palette-input", in: app)
        let focusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: input
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [focusExpectation], timeout: 5),
            .completed,
            "Cmd+T did not make the command palette input the keyboard focus owner"
        )
    }
}
