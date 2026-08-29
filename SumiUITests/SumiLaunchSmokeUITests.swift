import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
final class SumiLaunchSmokeUITests: SumiLaunchSmokeUITestCase {
    func testLaunchesMainWindow() throws {
        let app = try launchApp()

        XCTAssertTrue(app.windows.element(boundBy: 0).waitForExistence(timeout: 5))
        XCTAssertFalse(
            app.staticTexts["Recovering browser data…"].exists,
            "A clean launch must project the browser without recovery chrome."
        )
    }

    func testCollapsedFolderHoverPresentsPreviewWithoutTerminatingApp() throws {
        let fixture = try loadPersonalSidebarFixture()
        let folderID = try XCTUnwrap(fixture.folderID)
        let app = try launchApp(
            preferencesHomeURL: try prepareSelectedRegularTabPreferencesHome(
                tabURLString: "about:blank",
                tabName: "Folder Hover Oracle"
            )
        )
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        activatePersonalSpace(
            fixture,
            app: app,
            window: window,
            collapsedSidebar: false
        )

        let header = requireElement(
            withIdentifier: "folder-header-\(folderID)",
            in: app,
            window: window,
            collapsedSidebar: false
        )
        if accessibilityValue(of: header) == "expanded" {
            header.coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).click()
        }
        let headerID = "folder-header-\(folderID)"
        XCTAssertTrue(
            waitForAccessibilityValue(
                "collapsed",
                elementID: headerID,
                in: app,
                window: window,
                collapsedSidebar: false,
                timeout: 5
            ),
            "Folder did not finish collapsing before the hover check"
        )
        let collapsedHeader = requireElement(
            withIdentifier: headerID,
            in: app,
            window: window,
            collapsedSidebar: false
        )

        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)
        ).hover()
        collapsedHeader.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).hover()

        let preview = element(withIdentifier: "folder-preview-panel", in: app)
        if !preview.waitForExistence(timeout: 1.5) {
            window.coordinate(
                withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)
            ).hover()
            requireElement(
                withIdentifier: headerID,
                in: app,
                window: window,
                collapsedSidebar: false
            ).coordinate(
                withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
            ).hover()
        }
        XCTAssertTrue(
            preview.waitForExistence(timeout: 3),
            "Hovering a collapsed folder did not present its preview panel"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testSelectingCustomFolderIconDoesNotTerminateApp() throws {
        let fixture = try loadPersonalSidebarFixture()
        let folderID = try XCTUnwrap(fixture.folderID)
        let app = try launchApp(
            preferencesHomeURL: try prepareSmokePreferencesHome()
        )
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        activatePersonalSpace(
            fixture,
            app: app,
            window: window,
            collapsedSidebar: false
        )

        let folder = requireElement(
            withIdentifier: "folder-header-\(folderID)",
            in: app,
            window: window,
            collapsedSidebar: false
        )
        openSidebarContextMenu(
            on: folder,
            expectedMenuItem: "Edit",
            app: app
        )
        chooseContextMenuItem("Edit", app: app)

        let editor = element(
            withIdentifier: "folder-editor-popover",
            in: app
        )
        XCTAssertTrue(editor.waitForExistence(timeout: 5))

        let changeIcon = app.buttons["Change Icon"]
        XCTAssertTrue(changeIcon.waitForExistence(timeout: 5))
        changeIcon.click()

        let picker = element(
            withIdentifier: "folder-glyph-picker-panel",
            in: app
        )
        XCTAssertTrue(picker.waitForExistence(timeout: 5))

        let customIcon = app.buttons["School"]
        XCTAssertTrue(customIcon.waitForExistence(timeout: 5))
        customIcon.click()

        window.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(
            waitForNonExistence(picker, timeout: 5),
            "Escape did not close the custom folder icon picker"
        )
        XCTAssertTrue(editor.exists)

        let done = app.buttons["Done"]
        XCTAssertTrue(done.waitForExistence(timeout: 5))
        done.click()

        XCTAssertEqual(
            app.state,
            .runningForeground,
            "Selecting a custom folder icon terminated Sumi"
        )
        XCTAssertTrue(
            waitForNonExistence(editor, timeout: 5),
            "Saving the custom folder icon did not close the editor"
        )
    }

    func testRepeatedSettingsCommandKeepsSingleSettingsWindow() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let browserWindow = app.windows.element(boundBy: 0)

        XCTAssertTrue(browserWindow.waitForExistence(timeout: 5))
        browserWindow.typeKey(",", modifierFlags: .command)

        let settingsWindow = app.windows["General"]
        XCTAssertTrue(
            settingsWindow.waitForExistence(timeout: 5),
            "Command-comma should open the Settings window."
        )
        expectation(
            for: NSPredicate(format: "hasKeyboardFocus == true"),
            evaluatedWith: settingsWindow
        )
        waitForExpectations(timeout: 5)

        settingsWindow.typeKey(",", modifierFlags: .command)
        XCTAssertEqual(
            app.windows.matching(identifier: "General").count,
            1,
            "Repeating the Settings command should reuse the existing window."
        )
    }

    func testCommandCommaOpensSettingsWindow() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let browserWindow = app.windows.element(boundBy: 0)

        XCTAssertTrue(browserWindow.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)

        browserWindow.typeKey(",", modifierFlags: .command)

        XCTAssertTrue(
            app.windows["General"].waitForExistence(timeout: 5),
            "Command-comma should open the Settings window."
        )
    }

    func testCommandWClosesSettingsWithoutClosingBrowserTab() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let browserWindow = app.windows.element(boundBy: 0)

        XCTAssertTrue(browserWindow.waitForExistence(timeout: 5))
        openNewTabCommandPalette(in: app)
        let commandPalette = element(withIdentifier: "command-palette", in: app)
        XCTAssertTrue(commandPalette.waitForExistence(timeout: 5))

        browserWindow.typeKey(",", modifierFlags: .command)
        let settingsWindow = app.windows["General"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))

        settingsWindow.typeKey("w", modifierFlags: .command)

        XCTAssertTrue(
            waitForNonExistence(settingsWindow, timeout: 5),
            "Command-W should close the Settings window."
        )
        XCTAssertTrue(browserWindow.exists)
        XCTAssertTrue(
            commandPalette.exists,
            "Closing Settings must not close the active browser tab."
        )
    }

    func testCompletedRetirementHistoryLaunchesBrowserWithoutPlaceholder()
        throws {
        let preferencesHome = try prepareCompletedRetirementTombstonePreferencesHome()
        let fixture = try loadPersonalSidebarFixture()
        let app = try launchApp(preferencesHomeURL: preferencesHome)
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)
        XCTAssertTrue(
            element(
                withIdentifier: "space-icon-\(fixture.personalSpaceID)",
                in: app
            ).waitForExistence(timeout: 5),
            "Completed retirement history must project browser chrome instead of an empty launch shell."
        )
        XCTAssertFalse(app.staticTexts["Recovering browser data…"].exists)
    }

    func testClosingNewWindowKeepsOriginalBrowserWindowAlive() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let originalWindow = app.windows.element(boundBy: 0)

        XCTAssertTrue(originalWindow.waitForExistence(timeout: 5))
        XCTAssertEqual(app.windows.count, 1)
        let originalCloseButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.closeButton,
            inSearchRoot: originalWindow
        )
        XCTAssertTrue(
            waitForTrafficLightElementToBeVisibleAndEnabled(
                originalCloseButton,
                timeout: 5
            ),
            "Wait for startup recovery and command routing before sending Cmd+N."
        )

        app.typeKey("n", modifierFlags: .command)

        XCTAssertTrue(waitForWindowCount(2, in: app, timeout: 5))
        let newWindow = app.windows.element(boundBy: 0)
        let closeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.closeButton,
            inSearchRoot: newWindow
        )
        XCTAssertTrue(waitForTrafficLightElementToBeVisibleAndEnabled(closeButton, timeout: 3))

        closeButton.click()

        XCTAssertTrue(waitForWindowCount(1, in: app, timeout: 5))
        XCTAssertTrue(originalWindow.exists)
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testRendersSpaceSwitcherShell() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)
        let spaceIcon = element(withIdentifier: "space-icon-\(fixture.personalSpaceID)", in: app)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        XCTAssertTrue(spaceIcon.waitForExistence(timeout: 5))
    }

    func testNativeTrafficLightsAreHittableInNormalWindow() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        revealHoverSidebar(in: window)
        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testDockedSidebarKeepsNativeTrafficLightsWhenNoTabsExist() throws {
        let preferencesHome = try prepareEmptyDockedSidebarPreferencesHome()
        let app = try launchApp(preferencesHomeURL: preferencesHome)
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        assertNativeTrafficLightsHittable(in: app, window: window)

        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))

        assertNativeTrafficLightsHittable(in: app, window: window)

        let content = window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        for iteration in 0..<4 {
            let collapseToggle = app.buttons["Toggle Sidebar"].firstMatch
            XCTAssertTrue(
                collapseToggle.waitForExistence(timeout: 3),
                "Docked toggle is missing before cycle \(iteration)"
            )
            collapseToggle.click()
            content.hover()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))

            revealHoverSidebar(in: window)
            let expandToggle = app.buttons["Toggle Sidebar"].firstMatch
            XCTAssertTrue(
                expandToggle.waitForExistence(timeout: 3),
                "Collapsed toggle is missing during cycle \(iteration)"
            )
            expandToggle.click()
            content.hover()
            RunLoop.current.run(until: Date().addingTimeInterval(0.8))

            assertNativeTrafficLightsHittable(in: app, window: window)
        }
    }

    func testCollapsedEmptyFavoritesPlaceholderCanBeDismissed() throws {
        try skipUnlessInteractionE2E()

        let preferencesHome = try prepareEmptyDockedSidebarPreferencesHome(
            isSidebarVisible: false
        )
        let app = try launchApp(preferencesHomeURL: preferencesHome)
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        revealHoverSidebar(in: window)

        let dismissButton = app.buttons["favorite-placeholder-dismiss"]
        XCTAssertTrue(
            dismissButton.waitForExistence(timeout: 5),
            "Collapsed empty Favorite should expose its dismiss button"
        )

        dismissButton.click()

        XCTAssertTrue(
            waitForNonExistence(dismissButton, timeout: 5),
            "Dismissing the Favorites hint should collapse the placeholder"
        )
    }

    func testGreenTrafficLightHoverOpensCompactMenu() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let zoomButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.zoomButton,
            in: app
        )
        XCTAssertTrue(waitForTrafficLightElementToBeVisibleAndEnabled(zoomButton, timeout: 3))

        zoomButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        XCTAssertTrue(waitForTrafficLightElementToRemainVisibleAndEnabled(
            zoomButton,
            duration: SmokeUITiming.trafficLightHoverStabilityWindow
        ))

        window.typeKey(.escape, modifierFlags: [])
        XCTAssertTrue(waitForTrafficLightElementToBeVisibleAndEnabled(zoomButton, timeout: 2))
    }

    func testCloseTrafficLightHoverDoesNotTriggerCustomZoomMenu() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let closeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.closeButton,
            in: app
        )
        XCTAssertTrue(waitForTrafficLightElementToBeVisibleAndEnabled(closeButton, timeout: 3))

        closeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        XCTAssertTrue(waitForTrafficLightElementToRemainVisibleAndEnabled(
            closeButton,
            duration: SmokeUITiming.trafficLightHoverStabilityWindow
        ))
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        XCTAssertTrue(waitForTrafficLightElementToBeVisibleAndEnabled(closeButton, timeout: 2))
        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testTrafficLightHoverKeepsStandardButtonsStableAndHittable() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        assertNativeTrafficLightsHittable(in: app, window: window)

        let closeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.closeButton,
            inSearchRoot: app
        )
        let minimizeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.minimizeButton,
            inSearchRoot: app
        )
        let zoomButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.zoomButton,
            inSearchRoot: app
        )

        window.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        let unhoveredScreenshot = XCUIScreen.main.screenshot()

        let closeFrame = closeButton.frame
        closeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        XCTAssertTrue(waitForTrafficLightElementToBeVisibleAndEnabled(closeButton, timeout: 2))
        XCTAssertEqual(closeButton.frame, closeFrame)
        assertNativeTrafficLightGlyphsAppear(
            in: [closeButton, minimizeButton, zoomButton],
            comparedTo: unhoveredScreenshot
        )

        let zoomFrame = zoomButton.frame
        zoomButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        XCTAssertTrue(waitForTrafficLightElementToBeVisibleAndEnabled(zoomButton, timeout: 2))
        XCTAssertEqual(zoomButton.frame, zoomFrame)
        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testTrafficLightsStaySeparatedAfterWindowDoubleClickZoom() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        assertNativeTrafficLightsHittable(in: app, window: window)

        let chromeCoordinate = window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.05))
        chromeCoordinate.doubleClick()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testCollapsedHoverSidebarCanBeRevealedFromRestoredSession() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        revealHoverSidebar(in: window)
        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testCollapsedHoverSidebarShowsAvailableUpdatePill() throws {
        let app = try launchApp(
            preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false),
            additionalArguments: ["--sumi-debug-available-update"]
        )
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        revealHoverSidebar(in: window)

        let updatePill = app.staticTexts["New Sumi Version Available"]
        XCTAssertTrue(
            updatePill.waitForExistence(timeout: 3),
            "An available update should use the standard hover-expanding pill in a collapsed sidebar."
        )
        updatePill.hover()
        XCTAssertTrue(app.buttons["Restart and Update"].waitForExistence(timeout: 3))
    }

    func testCollapsedHoverSidebarShowsCompletedUpdateCard() throws {
        let app = try launchApp(
            preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false),
            additionalArguments: ["--sumi-debug-update-notice"]
        )
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        revealHoverSidebar(in: window)

        XCTAssertTrue(app.staticTexts["Update Complete!"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.descendants(matching: .any)["What's new in Sumi"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Support us"].exists)
        XCTAssertTrue(app.descendants(matching: .any)["Something broke?"].exists)
    }

    func testAboutAvailableUpdateHasNoExplanatorySubtitle() throws {
        let app = try launchApp(
            preferencesHomeURL: try prepareSmokePreferencesHome(),
            additionalArguments: ["--sumi-debug-available-update"]
        )
        let browserWindow = app.windows.element(boundBy: 0)

        XCTAssertTrue(browserWindow.waitForExistence(timeout: 5))
        browserWindow.typeKey(",", modifierFlags: .command)

        let settingsWindow = app.windows["General"]
        XCTAssertTrue(settingsWindow.waitForExistence(timeout: 5))
        let aboutRow = app.staticTexts["About Sumi"].firstMatch
        XCTAssertTrue(aboutRow.waitForExistence(timeout: 3))
        aboutRow.click()

        let updateButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH %@", "Update to Sumi ")
        ).firstMatch
        XCTAssertTrue(updateButton.waitForExistence(timeout: 3))
        XCTAssertFalse(app.staticTexts["Download and install the update with Sparkle."].exists)
    }

    func testCollapsedSidebarCarriesTrafficLightPlaceholderDuringReveal() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        openNewTabCommandPalette(in: app)
        XCTAssertTrue(
            waitForCommandPalette(in: app, timeout: 10),
            "URL Hub did not appear before opening example.com"
        )
        let input = element(withIdentifier: "command-palette-input", in: app)
        XCTAssertTrue(input.isHittable, "URL Hub input is not hittable")
        try pasteText("https://example.com", into: input, in: app)
        input.typeKey(.return, modifierFlags: [])

        let urlBar = app.staticTexts.matching(identifier: "sidebar-urlbar").firstMatch
        let exampleDotComIsActive = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value CONTAINS[c] %@", "example.com"),
            object: urlBar
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [exampleDotComIsActive], timeout: 20),
            .completed,
            "example.com must be the active page before the sidebar transition is exercised."
        )

        let trafficLightFrames = [
            BrowserWindowControlIdentifiers.closeButton,
            BrowserWindowControlIdentifiers.minimizeButton,
            BrowserWindowControlIdentifiers.zoomButton,
        ].map {
            element(withIdentifier: $0, inSearchRoot: app).frame
        }
        let sidebarToggle = app.buttons["Toggle Sidebar"].firstMatch
        XCTAssertTrue(sidebarToggle.waitForExistence(timeout: 3))
        sidebarToggle.click()
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        XCUIApplication(bundleIdentifier: "com.apple.finder").activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        app.activate()
        RunLoop.current.run(until: Date().addingTimeInterval(0.4))
        assertTrafficLightClusterIsNotDrawn(in: trafficLightFrames)

        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.2))
        let content = window.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.5))
        for _ in 0..<4 {
            edge.withOffset(CGVector(dx: 2, dy: 0)).hover()
            RunLoop.current.run(until: Date().addingTimeInterval(0.08))
            content.hover()
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
        }
        edge.withOffset(CGVector(dx: 2, dy: 0)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        let closeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.closeButton,
            inSearchRoot: app
        )
        XCTAssertTrue(waitForTrafficLightElementToBeVisibleAndEnabled(closeButton, timeout: 2))
    }

    func testLaunchWithPersistedBrightThemeDoesNotRenderDominantBlackWindow() throws {
        let preferencesHomeURL = try prepareStartupThemeSmokeFixture()
        let app = try launchApp(preferencesHomeURL: preferencesHomeURL)
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let blackRatio = try dominantBlackPixelRatio(in: window.screenshot())
        XCTAssertLessThan(blackRatio, 0.35)
    }

    private func waitForWindowCount(
        _ expectedCount: Int,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if app.windows.count == expectedCount {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        } while Date() < deadline
        return app.windows.count == expectedCount
    }
}
