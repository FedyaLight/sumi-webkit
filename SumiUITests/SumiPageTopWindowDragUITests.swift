import Foundation
import XCTest

/// Window-drag coverage for the frameless top band.
///
/// Browser windows disable system titlebar dragging
/// (see SumiBrowserWindowShellConfiguration.isMovable) because the system
/// drag band overlays the page viewport. Those system paths are HID-driven
/// and never see XCUITest input, so they are covered by the isMovable
/// configuration tests plus this manual check: drag from the top of any web
/// page with a real mouse — the window must stay put and page text must
/// select; drag the sidebar control strip — the window must follow. These
/// UI tests guard everything synthetic input can reach: no view-level drag
/// affordance may capture drags over the page top, and the control strip
/// gesture keeps serving window gestures.
@MainActor
final class SumiPageTopWindowDragUITests: SumiLaunchSmokeUITestCase {
    private func launchWindowWithRenderedTopBand() throws -> (app: XCUIApplication, window: XCUIElement, server: SumiUIOracleHTTPServer) {
        let marker = "SUMI-TOP-DRAG-ORACLE"
        let server = try SumiUIOracleHTTPServer(
            path: "top-drag-\(UUID().uuidString.prefix(8)).html",
            html: """
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"></head>
            <body style="margin: 0">
              <h1 id="result" style="position: absolute; top: 8px; left: 16px; font: 700 15px system-ui">
                \(marker)
              </h1>
            </body>
            </html>
            """
        )

        let app = try launchApp(
            preferencesHomeURL: try prepareSmokePreferencesHome(),
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 10), "The browser window did not appear")

        openNewTabCommandPalette(in: app)
        XCTAssertTrue(
            waitForCommandPalette(in: app, timeout: 10),
            "URL Hub did not appear for the top-drag fixture"
        )
        let input = element(withIdentifier: "command-palette-input", in: app)
        XCTAssertTrue(input.isHittable, "URL Hub input is not hittable")
        try pasteText(server.pageURL.absoluteString, into: input, in: app)
        wait(
            for: NSPredicate(format: "value == %@", server.pageURL.absoluteString),
            on: input,
            timeout: 10,
            message: "URL Hub did not receive the top-drag fixture URL"
        )
        input.typeKey(.return, modifierFlags: [])
        wait(
            for: NSPredicate(format: "exists == false"),
            on: element(withIdentifier: "command-palette-input", in: app),
            timeout: 20,
            message: "URL Hub did not dismiss after navigation"
        )

        let expectedDisplayedHost = try XCTUnwrap(server.pageURL.host)
        let urlBar = app.staticTexts.matching(identifier: "sidebar-urlbar").firstMatch
        wait(
            for: NSPredicate(format: "value == %@", expectedDisplayedHost),
            on: urlBar,
            timeout: 20,
            message: "The navigation did not reach the loopback fixture; url bar: \(urlBar.debugDescription)"
        )

        let renderedDocument = window.descendants(matching: .any).matching(
            NSPredicate(
                format: "value CONTAINS %@ OR label CONTAINS %@",
                marker,
                marker
            )
        ).firstMatch
        wait(
            for: NSPredicate(format: "exists == true"),
            on: renderedDocument,
            timeout: 30,
            message: "The oracle page did not render at the top of the window"
        )
        return (app, window, server)
    }

    func testDraggingAtPageTopDoesNotMoveWindow() throws {
        let (_, window, server) = try launchWindowWithRenderedTopBand()
        defer { server.stop() }

        let start = window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.75, dy: 30 / window.frame.height)
        )
        let frameBefore = window.frame
        start.press(forDuration: 0.05, thenDragTo: start.withOffset(CGVector(dx: 120, dy: 0)))
        let frameAfter = window.frame

        XCTAssertEqual(
            frameAfter.origin.x,
            frameBefore.origin.x,
            accuracy: 2,
            "Dragging over the top of the page moved the window horizontally"
        )
        XCTAssertEqual(
            frameAfter.origin.y,
            frameBefore.origin.y,
            accuracy: 2,
            "Dragging over the top of the page moved the window vertically"
        )
    }

    func testSidebarControlStripKeepsWindowGestureAffordances() throws {
        let (app, window, server) = try launchWindowWithRenderedTopBand()
        defer { server.stop() }

        let toggle = app.buttons["Toggle Sidebar"].firstMatch
        XCTAssertTrue(
            toggle.waitForExistence(timeout: 10),
            "Sidebar toggle not found to anchor the control strip"
        )

        func freshStripPoint() -> XCUICoordinate {
            let currentWindowFrame = window.frame
            let currentToggleFrame = toggle.frame
            return window.coordinate(
                withNormalizedOffset: CGVector(
                    dx: (currentToggleFrame.maxX + 30 - currentWindowFrame.minX) / currentWindowFrame.width,
                    dy: (currentToggleFrame.midY - currentWindowFrame.minY) / currentWindowFrame.height
                )
            )
        }

        // The strip's WindowDragGesture is the window-drag affordance now that
        // system titlebar dragging is off. Its double-click zoom branch is
        // observable through plain event delivery; the drag branch enters a
        // HID-driven modal loop that synthetic events cannot drive.
        let frameBefore = window.frame
        freshStripPoint().doubleClick()

        var zoomedFrame = window.frame
        let zoomDeadline = Date().addingTimeInterval(5)
        while Date() < zoomDeadline, framesDiffer(zoomedFrame, frameBefore, by: 2) == false {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            zoomedFrame = window.frame
        }
        XCTAssertTrue(
            framesDiffer(zoomedFrame, frameBefore, by: 2),
            "Double-clicking the sidebar control strip did not zoom the window"
        )

        // Let the zoom animation settle before sending the restoring click.
        RunLoop.current.run(until: Date().addingTimeInterval(0.8))
        freshStripPoint().doubleClick()

        var restoredFrame = window.frame
        let restoreDeadline = Date().addingTimeInterval(5)
        while Date() < restoreDeadline, framesDiffer(restoredFrame, frameBefore, by: 2) {
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
            restoredFrame = window.frame
        }
        XCTAssertFalse(
            framesDiffer(restoredFrame, frameBefore, by: 2),
            "Double-clicking the sidebar control strip again did not restore the window: "
                + "before=\(frameBefore) after=\(restoredFrame)"
        )
    }

    private func framesDiffer(
        _ lhs: CGRect,
        _ rhs: CGRect,
        by tolerance: CGFloat
    ) -> Bool {
        abs(lhs.minX - rhs.minX) > tolerance
            || abs(lhs.minY - rhs.minY) > tolerance
            || abs(lhs.width - rhs.width) > tolerance
            || abs(lhs.height - rhs.height) > tolerance
    }
}
