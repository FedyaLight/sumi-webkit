import Foundation
import XCTest

@MainActor
final class SumiFindInPageFocusUITests: SumiLaunchSmokeUITestCase {
    func testFindInPageCommandImmediatelyAcceptsKeyboardInput() throws {
        let fixture = try prepareLocalPage()
        let app = try launchApp(
            preferencesHomeURL: try prepareSmokePreferencesHome()
        )
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(waitForCommandPalette(in: app, timeout: 5))
        let paletteInput = element(
            withIdentifier: "command-palette-input",
            in: app
        )
        XCTAssertTrue(paletteInput.waitForExistence(timeout: 5))
        paletteInput.click()
        paletteInput.typeText(fixture.url.absoluteString)
        app.typeKey(.return, modifierFlags: [])
        XCTAssertTrue(
            waitForNonExistence(paletteInput, timeout: 20),
            "Fixture navigation did not dismiss the command palette"
        )

        let renderedMarker = window.descendants(matching: .any).matching(
            NSPredicate(
                format: "value == %@ OR label == %@",
                fixture.marker,
                fixture.marker
            )
        ).firstMatch
        XCTAssertTrue(
            renderedMarker.waitForExistence(timeout: 30),
            "Fixture page did not finish loading before the shortcut"
        )

        app.typeKey("f", modifierFlags: [.command])

        let input = element(
            withIdentifier: "FindInPageController.textField",
            in: app
        )
        XCTAssertTrue(
            input.waitForExistence(timeout: 5),
            "Find in Page did not appear after its browser command"
        )

        app.typeText("sumi")

        XCTAssertTrue(
            waitForValue("sumi", in: input, timeout: 5),
            "Find in Page did not accept typing immediately after opening"
        )
        XCTAssertTrue(
            waitForKeyboardFocus(in: input, timeout: 2),
            "Find in Page input is not the keyboard focus owner"
        )
    }

    private func prepareLocalPage() throws -> (url: URL, marker: String) {
        let directory = try makeSmokeScratchDirectory(
            prefix: "SumiFindInPageFocus"
        )
        smokeAppSupportDirectories.append(directory)
        let pageURL = directory.appendingPathComponent("find-focus.html")
        let marker = "SUMI-FIND-FOCUS-\(UUID().uuidString.prefix(8))"
        try """
        <!doctype html>
        <html>
        <head><meta charset="utf-8"><title>Find Focus</title></head>
        <body><p>\(marker)</p><p>sumi focus fixture</p></body>
        </html>
        """.write(to: pageURL, atomically: true, encoding: .utf8)
        return (pageURL, marker)
    }

    private func waitForValue(
        _ value: String,
        in element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == %@", value),
            object: element
        )
        return XCTWaiter().wait(
            for: [expectation],
            timeout: timeout
        ) == .completed
    }

    private func waitForKeyboardFocus(
        in element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: element
        )
        return XCTWaiter().wait(
            for: [expectation],
            timeout: timeout
        ) == .completed
    }
}
