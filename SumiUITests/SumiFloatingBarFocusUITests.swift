import Foundation
import XCTest

@MainActor
final class SumiFloatingBarFocusUITests: SumiLaunchSmokeUITestCase {
    func testCommandTFocusesFloatingBarInputForImmediateTyping() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(
            waitForFloatingBar(in: app, timeout: 5),
            "Floating bar did not appear after Cmd+T"
        )

        // Type immediately, without clicking the bar. The typed characters must
        // land in the floating bar input.
        let typed = "hello"
        app.typeText(typed)

        let input = element(withIdentifier: "floating-bar-input", in: app)
        XCTAssertTrue(
            waitForFloatingBarInputValue(typed, input: input, timeout: 3),
            "Floating bar input did not receive typed text; value: \(String(describing: input.value))"
        )
    }

    private func waitForFloatingBarInputValue(
        _ expected: String,
        input: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if (input.value as? String) == expected {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return (input.value as? String) == expected
    }
}
