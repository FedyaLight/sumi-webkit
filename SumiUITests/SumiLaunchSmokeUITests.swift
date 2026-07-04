import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
final class SumiLaunchSmokeUITests: SumiLaunchSmokeUITestCase {
    func testLaunchesMainWindow() {
        let app = launchApp()

        XCTAssertTrue(app.windows.element(boundBy: 0).waitForExistence(timeout: 5))
    }

    func testRendersSpaceSwitcherShell() {
        let app = launchApp()
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "space-icon-")
        let spaceIcons = app.descendants(matching: .any).matching(predicate)

        XCTAssertTrue(spaceIcons.firstMatch.waitForExistence(timeout: 5))
    }

    func testNativeTrafficLightsAreHittableInNormalWindow() throws {
        let app = launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        revealHoverSidebar(in: window)
        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testGreenTrafficLightHoverOpensCompactMenu() throws {
        let app = launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
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
        let app = launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
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
        let app = launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
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
        let app = launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        assertNativeTrafficLightsHittable(in: app, window: window)

        let chromeCoordinate = window.coordinate(withNormalizedOffset: CGVector(dx: 0.55, dy: 0.05))
        chromeCoordinate.doubleClick()
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))

        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testCollapsedHoverSidebarKeepsNativeTrafficLightsHittable() throws {
        let app = launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testCollapsedHoverSidebarCanBeRevealedFromRestoredSession() throws {
        let app = launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        revealHoverSidebar(in: window)
        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testLaunchWithPersistedBrightThemeDoesNotRenderDominantBlackWindow() throws {
        let preferencesHomeURL = try prepareStartupThemeSmokeFixture()
        let app = launchApp(preferencesHomeURL: preferencesHomeURL)
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let blackRatio = try dominantBlackPixelRatio(in: window.screenshot())
        XCTAssertLessThan(blackRatio, 0.35)
    }
}
