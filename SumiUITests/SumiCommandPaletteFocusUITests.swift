import Carbon
import Foundation
import XCTest

@MainActor
final class SumiCommandPaletteFocusUITests: SumiLaunchSmokeUITestCase {
    func testNewTabCommandMakesCommandPaletteInputKeyboardFocusOwner() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        openNewTabCommandPalette(in: app)
        XCTAssertTrue(
            waitForCommandPalette(in: app, timeout: 5),
            "Command palette did not appear after the New Tab command"
        )

        let input = element(withIdentifier: "command-palette-input", in: app)
        let focusExpectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "hasKeyboardFocus == true"),
            object: input
        )
        XCTAssertEqual(
            XCTWaiter().wait(for: [focusExpectation], timeout: 5),
            .completed,
            "The New Tab command did not make the command palette input the keyboard focus owner"
        )
    }

    func testTabToSearchAndEscapeKeepInputFocused() throws {
        try withABCInputSource {
            let app = try launchApp(
                preferencesHomeURL: try prepareSmokePreferencesHome()
            )
            let window = app.windows.element(boundBy: 0)
            XCTAssertTrue(window.waitForExistence(timeout: 5))

            openNewTabCommandPalette(in: app)
            XCTAssertTrue(waitForCommandPalette(in: app, timeout: 5))

            let input = element(
                withIdentifier: "command-palette-input",
                in: app
            )
            XCTAssertTrue(input.waitForExistence(timeout: 5))
            XCTAssertTrue(waitForKeyboardFocus(in: input, timeout: 5))
            input.typeText("YouTube")

            let siteSearchOffer = app.staticTexts.matching(
                NSPredicate(
                    format: "label == %@ OR value == %@",
                    "Search YouTube",
                    "Search YouTube"
                )
            ).firstMatch
            XCTAssertTrue(siteSearchOffer.waitForExistence(timeout: 5))

            input.typeKey(.tab, modifierFlags: [])

            XCTAssertTrue(
                waitForValue("", in: input, timeout: 5),
                "Tab did not enter the scoped YouTube search mode"
            )
            XCTAssertTrue(
                waitForKeyboardFocus(in: input, timeout: 5),
                "Site Search did not retain command-palette input focus"
            )
            XCTAssertFalse(siteSearchOffer.exists)

            input.typeText("music")
            input.typeKey(.escape, modifierFlags: [])

            XCTAssertTrue(
                waitForValue("", in: input, timeout: 5),
                "Escape did not return from Site Search to Everything"
            )
            XCTAssertTrue(
                waitForKeyboardFocus(in: input, timeout: 5),
                "Leaving Site Search did not restore command-palette input focus"
            )
            XCTAssertTrue(waitForCommandPalette(in: app, timeout: 2))
            assertFirstResultIsAtTop(in: app)
        }
    }

    func testTypingAfterManualActionsScrollReturnsResultsToTop() throws {
        try withABCInputSource {
            let app = try launchApp(
                preferencesHomeURL: try prepareSmokePreferencesHome()
            )
            XCTAssertTrue(
                app.windows.element(boundBy: 0).waitForExistence(timeout: 5)
            )

            openNewTabCommandPalette(in: app)
            XCTAssertTrue(waitForCommandPalette(in: app, timeout: 5))
            let input = element(
                withIdentifier: "command-palette-input",
                in: app
            )
            XCTAssertTrue(waitForKeyboardFocus(in: input, timeout: 5))
            input.typeKey(.tab, modifierFlags: [])

            let results = app.scrollViews[
                "command-palette-results"
            ]
            XCTAssertTrue(results.waitForExistence(timeout: 5))
            results.scroll(byDeltaX: 0, deltaY: -240)
            XCTAssertTrue(
                waitForKeyboardFocus(in: input, timeout: 2),
                "Scrolling results transferred keyboard focus from the input"
            )

            input.typeText("Settings")

            let settings = app.buttons.matching(
                NSPredicate(
                    format: "label == %@",
                    "Run command, Settings"
                )
            ).firstMatch
            XCTAssertTrue(settings.waitForExistence(timeout: 5))
            assertFirstResultIsAtTop(in: app)
        }
    }

    func testSplitCommandFromPaletteCreatesSplit() throws {
        try withABCInputSource {
            let fixture = try loadPersonalSidebarFixture()
            let launcherID = try XCTUnwrap(fixture.topLevelLauncherID)
            let app = try launchApp(
                preferencesHomeURL: try prepareSmokePreferencesHome()
            )
            XCTAssertTrue(
                app.windows.element(boundBy: 0).waitForExistence(timeout: 5)
            )
            try activateSmokeLauncher(id: launcherID, app: app)

            openNewTabCommandPalette(in: app)
            XCTAssertTrue(waitForCommandPalette(in: app, timeout: 5))
            let input = element(
                withIdentifier: "command-palette-input",
                in: app
            )
            XCTAssertTrue(waitForKeyboardFocus(in: input, timeout: 5))
            input.typeText("Add Right Split")

            let result = app.buttons.matching(
                NSPredicate(
                    format: "label == %@",
                    "Run command, Add Right Split"
                )
            ).firstMatch
            XCTAssertTrue(result.waitForExistence(timeout: 5))
            result.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).click()

            XCTAssertTrue(
                app.splitGroups.firstMatch.waitForExistence(timeout: 5),
                "Add Right Split did not create a browser content split"
            )
        }
    }

    func testSplitResultUsesMemberTitlesInsteadOfTabCount() throws {
        try withABCInputSource {
            let fixture = try loadPersonalSidebarFixture()
            let launcherID = try XCTUnwrap(fixture.topLevelLauncherID)
            let app = try launchApp(
                preferencesHomeURL: try prepareSmokePreferencesHome()
            )
            XCTAssertTrue(
                app.windows.element(boundBy: 0).waitForExistence(timeout: 5)
            )
            try activateSmokeLauncher(id: launcherID, app: app)

            openNewTabCommandPalette(in: app)
            XCTAssertTrue(waitForCommandPalette(in: app, timeout: 5))
            var input = element(
                withIdentifier: "command-palette-input",
                in: app
            )
            XCTAssertTrue(waitForKeyboardFocus(in: input, timeout: 5))
            input.typeText("Add Right Split")

            let splitCommand = app.buttons.matching(
                NSPredicate(
                    format: "label == %@",
                    "Run command, Add Right Split"
                )
            ).firstMatch
            XCTAssertTrue(splitCommand.waitForExistence(timeout: 5))
            splitCommand.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).click()

            input = element(
                withIdentifier: "command-palette-input",
                in: app
            )
            XCTAssertTrue(waitForKeyboardFocus(in: input, timeout: 5))
            let clearedSplitPicker = XCTNSPredicateExpectation(
                predicate: NSPredicate(format: "value == %@", ""),
                object: input
            )
            XCTAssertEqual(
                XCTWaiter.wait(for: [clearedSplitPicker], timeout: 5),
                .completed,
                "Split picker did not clear the command query"
            )
            input.typeText("https://example.com/sumi-split-partner")
            input.typeKey(.return, modifierFlags: [])
            XCTAssertTrue(app.splitGroups.firstMatch.waitForExistence(timeout: 5))

            openNewTabCommandPalette(in: app)
            XCTAssertTrue(waitForCommandPalette(in: app, timeout: 5))
            input = element(
                withIdentifier: "command-palette-input",
                in: app
            )
            XCTAssertTrue(waitForKeyboardFocus(in: input, timeout: 5))
            input.typeText("Example Domain")

            let splitResult = app.buttons.matching(
                NSPredicate(
                    format:
                        "label BEGINSWITH %@ AND label CONTAINS %@",
                    "Switch to split view",
                    "Example Domain"
                )
            ).firstMatch
            XCTAssertTrue(
                splitResult.waitForExistence(timeout: 5),
                "Split results must identify their member tabs, not only their count"
            )

            input.typeKey(.downArrow, modifierFlags: [])

            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Command Palette split member presentation"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
    }

    func testCloseTabOnLauncherIsPresentedAsUnloadAndUnloadsRuntime() throws {
        try withABCInputSource {
            let fixture = try loadPersonalSidebarFixture()
            let launcherID = try XCTUnwrap(fixture.topLevelLauncherID)
            let launcherRowID = "space-pinned-shortcut-\(launcherID)"
            let app = try launchApp(
                preferencesHomeURL: try prepareSmokePreferencesHome()
            )
            XCTAssertTrue(
                app.windows.element(boundBy: 0).waitForExistence(timeout: 5)
            )
            try activateSmokeLauncher(id: launcherID, app: app)

            openNewTabCommandPalette(in: app)
            XCTAssertTrue(waitForCommandPalette(in: app, timeout: 5))
            let input = element(
                withIdentifier: "command-palette-input",
                in: app
            )
            XCTAssertTrue(waitForKeyboardFocus(in: input, timeout: 5))
            input.typeText("Close Tab")

            let unloadResult = app.buttons.matching(
                NSPredicate(
                    format: "label == %@",
                    "Run command, Unload"
                )
            ).firstMatch
            XCTAssertTrue(
                unloadResult.waitForExistence(timeout: 5),
                "Active launchers must present Close Tab as Unload"
            )
            unloadResult.click()

            XCTAssertTrue(
                element(
                    withIdentifier: launcherRowID,
                    in: app
                ).waitForExistence(timeout: 5),
                "Unload removed the durable launcher"
            )
            XCTAssertTrue(
                waitForSelectionState(
                    selected: false,
                    elementID: launcherRowID,
                    in: app,
                    timeout: 5
                ),
                "Unload left the launcher runtime selected"
            )
        }
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

    private func waitForSelectionState(
        selected: Bool,
        elementID: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let candidate = element(withIdentifier: elementID, in: app)
            if candidate.exists {
                let value = accessibilityValue(of: candidate)
                let stateMatches = selected
                    ? value == "selected" || candidate.isSelected
                    : value != "selected" && !candidate.isSelected
                if stateMatches {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return false
    }

    private func assertFirstResultIsAtTop(
        in app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let results = app.scrollViews[
            "command-palette-results"
        ]
        XCTAssertTrue(
            results.waitForExistence(timeout: 5),
            "Command palette results are missing",
            file: file,
            line: line
        )
        let first = results.buttons.firstMatch
        XCTAssertTrue(
            first.waitForExistence(timeout: 5),
            "Command palette has no first result",
            file: file,
            line: line
        )
        XCTAssertTrue(
            first.isHittable,
            "The first result is clipped after the result set changes",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            first.frame.minY,
            results.frame.minY + first.frame.height * 0.5,
            "The result list did not return to its top edge",
            file: file,
            line: line
        )
    }

    private func activateSmokeLauncher(
        id launcherID: String,
        app: XCUIApplication
    ) throws {
        openNewTabCommandPalette(in: app)
        XCTAssertTrue(waitForCommandPalette(in: app, timeout: 5))

        let input = element(
            withIdentifier: "command-palette-input",
            in: app
        )
        XCTAssertTrue(waitForKeyboardFocus(in: input, timeout: 5))
        input.typeText("Smoke Launcher")

        let result = app.buttons.matching(
            NSPredicate(
                format: "label == %@",
                "Switch to tab, Smoke Launcher"
            )
        ).firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        result.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        XCTAssertTrue(
            waitForSelectionState(
                selected: true,
                elementID: "space-pinned-shortcut-\(launcherID)",
                in: app,
                timeout: 5
            ),
            "Clicking Switch to Tab did not activate the unloaded launcher"
        )
    }

    private func inputSourceID(_ source: TISInputSource) -> String? {
        guard let pointer = TISGetInputSourceProperty(
            source,
            kTISPropertyInputSourceID
        ) else {
            return nil
        }
        return Unmanaged<CFString>.fromOpaque(pointer)
            .takeUnretainedValue() as String
    }

    private func selectInputSource(id: String) throws {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        let sources = TISCreateInputSourceList(filter, false)
            .takeRetainedValue() as! [TISInputSource]
        let source = try XCTUnwrap(sources.first)
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            throw FixtureError.missingValue(
                "Unable to select input source \(id): OSStatus \(status)"
            )
        }

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let current = TISCopyCurrentKeyboardInputSource()
                .takeRetainedValue()
            if inputSourceID(current) == id {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw FixtureError.missingValue(
            "Input source \(id) did not become current"
        )
    }

    private func withABCInputSource(
        _ body: () throws -> Void
    ) throws {
        let currentInputSource =
            TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let previousInputSourceID = try XCTUnwrap(
            inputSourceID(currentInputSource)
        )
        try selectInputSource(id: "com.apple.keylayout.ABC")
        defer {
            do {
                try selectInputSource(id: previousInputSourceID)
            } catch {
                XCTFail(
                    "Unable to restore input source \(previousInputSourceID): "
                        + "\(error)"
                )
            }
        }
        try body()
    }
}
