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

        originalWindow.typeKey("n", modifierFlags: .command)

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

        app.typeKey(.escape, modifierFlags: [])
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
        let zoomButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.zoomButton,
            inSearchRoot: app
        )

        let closeFrame = closeButton.frame
        closeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
        XCTAssertTrue(waitForTrafficLightElementToBeVisibleAndEnabled(closeButton, timeout: 2))
        XCTAssertEqual(closeButton.frame, closeFrame)

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

    func testCollapsedHoverSidebarKeepsNativeTrafficLightsHittable() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testCollapsedHoverSidebarWithdrawsTrafficLightsWhenOverlayCloses() throws {
        _ = try loadPersonalSidebarFixture()
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        revealHoverSidebar(in: window)
        assertNativeTrafficLightsHittable(in: app, window: window)

        // Moving off the overlay closes it; the buttons ride it out and must stop responding.
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.7, dy: 0.6)).hover()
        assertNativeTrafficLightsHidden(in: app, window: window)
    }

    func testCollapsedHoverSidebarCanBeRevealedFromRestoredSession() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        revealHoverSidebar(in: window)
        assertNativeTrafficLightsHittable(in: app, window: window)
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
