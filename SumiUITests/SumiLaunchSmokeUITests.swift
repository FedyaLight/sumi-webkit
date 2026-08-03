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
        let app = try launchApp()
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

        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)
        ).hover()
        header.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).hover()

        XCTAssertTrue(
            element(withIdentifier: "folder-preview-panel", in: app)
                .waitForExistence(timeout: 3),
            "Hovering a collapsed folder did not present its preview panel"
        )
        XCTAssertEqual(app.state, .runningForeground)
    }

    func testSettingsMenuOpensSettingsWindow() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let browserWindow = app.windows.element(boundBy: 0)

        XCTAssertTrue(browserWindow.waitForExistence(timeout: 5))
        app.menuBars.menuBarItems["Sumi"].click()
        let settingsMenuItems = app.menuItems.matching(identifier: "Settings…")
        XCTAssertEqual(
            settingsMenuItems.count,
            1,
            "The application menu should contain exactly one Settings command."
        )
        settingsMenuItems.firstMatch.click()

        let settingsWindow = app.windows["General"]
        XCTAssertTrue(
            settingsWindow.waitForExistence(timeout: 5),
            "The application menu should open the Settings window."
        )

        app.menuBars.menuBarItems["Sumi"].click()
        XCTAssertEqual(
            app.menuItems.matching(identifier: "Settings…").count,
            1,
            "The Settings window should preserve the single Settings command."
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

        app.menuBars.menuBarItems["File"].click()
        app.menuItems["New Window"].click()

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

        let dismissButton = app.buttons["essentials-placeholder-dismiss"]
        XCTAssertTrue(
            dismissButton.waitForExistence(timeout: 5),
            "Collapsed empty Essentials should expose its dismiss button"
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
