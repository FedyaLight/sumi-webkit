import CoreGraphics
import Foundation
import XCTest

/// Regression: expanding a glance into a regular tab must leave the promoted
/// page's WebKit mouse pipeline alive. Re-parenting inside the window used to
/// strand WebKit's mouse tracking observer in its exited state (no
/// mouseEntered is delivered for re-registered assumeInside areas while the
/// pointer already hovers them), leaving CSS :hover dead and the cursor stuck
/// as an arrow until the pointer left and re-entered the view.
@MainActor
final class SumiGlancePromotionHoverUITests: SumiLaunchSmokeUITestCase {
    func testGlanceExpandKeepsHoverAndCursorAlive() throws {
        let dumpFile = URL(fileURLWithPath: "/tmp/sumi-cursor-dump-xctest.txt")
        try? FileManager.default.removeItem(at: dumpFile)

        let targetServer = try SumiUIOracleHTTPServer(
            path: "target.html",
            html: """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8"><title>Glance Target</title></head>
            <body style="margin:0">
            <a href="#" style="display:block;width:100%;height:40%;background:#eed;font-size:48px;text-align:center">HOVER ME FOR POINTING HAND</a>
            </body></html>
            """
        )
        defer { targetServer.stop() }
        let sourceServer = try SumiUIOracleHTTPServer(
            path: "source.html",
            html: """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8"><title>Glance Source</title></head>
            <body style="margin:0">
            <a href="\(targetServer.pageURL.absoluteString)" style="display:block;width:100%;height:40%;background:#dde;font-size:48px;text-align:center">BIG LINK TO TARGET</a>
            </body></html>
            """
        )
        defer { sourceServer.stop() }

        let app = try launchApp(
            preferencesHomeURL: try prepareSmokePreferencesHome(),
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
                "SUMI_CURSOR_DIAGNOSTICS": "1",
                "SUMI_CURSOR_DIAGNOSTICS_FILE": dumpFile.path,
            ]
        )
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 15), "No browser window appeared")

        openNewTabCommandPalette(in: app)
        XCTAssertTrue(waitForCommandPalette(in: app, timeout: 10), "URL Hub did not appear")
        let input = element(withIdentifier: "command-palette-input", in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5), "No URL Hub input")
        try pasteText(sourceServer.pageURL.absoluteString, into: input, in: app)
        input.typeKey(.return, modifierFlags: [])

        let sourceLink = window.links["BIG LINK TO TARGET"]
        XCTAssertTrue(
            sourceLink.waitForExistence(timeout: 15),
            "Source page link did not appear"
        )
        let linkCenter = CGPoint(
            x: sourceLink.frame.midX,
            y: sourceLink.frame.midY
        )
        postClick(at: linkCenter, modifiers: .maskAlternate)

        let expandButton = element(withIdentifier: "glance-action-open-in-tab", in: app)
        XCTAssertTrue(
            expandButton.waitForExistence(timeout: 15),
            "Glance expand button did not appear after option-clicking a link"
        )
        expandButton.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()

        let promotedLink = window.links["HOVER ME FOR POINTING HAND"]
        XCTAssertTrue(
            promotedLink.waitForExistence(timeout: 15),
            "Promoted page link did not appear after expand"
        )

        let hoverCenter = CGPoint(
            x: promotedLink.frame.midX,
            y: promotedLink.frame.midY
        )
        for step in 0..<25 {
            postMouseMoved(
                to: CGPoint(
                    x: hoverCenter.x + CGFloat(step % 5) * 5,
                    y: hoverCenter.y
                )
            )
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }
        RunLoop.current.run(until: Date().addingTimeInterval(3))

        let dump = (try? String(contentsOf: dumpFile, encoding: .utf8)) ?? ""
        let targetLines = dump.split(separator: "\n").filter {
            $0.contains("url=target.html")
        }
        // One dump line carries both facts, so the pointing hand cannot come
        // from chrome hover (e.g. the expand button) at a different moment.
        XCTAssertTrue(
            targetLines.contains {
                $0.contains("\"hoverLink\":true") && $0.contains("cursor=pointingHand")
            },
            "Promoted page never reported live hover with a pointing hand after expand; cursor pipeline is dead.\nLast target lines:\n\(targetLines.suffix(6).joined(separator: "\n"))"
        )
    }

    private func postClick(at point: CGPoint, modifiers: CGEventFlags) {
        postMouseEvent(.leftMouseDown, at: point, modifiers: modifiers)
        postMouseEvent(.leftMouseUp, at: point, modifiers: modifiers)
    }

    private func postMouseMoved(to point: CGPoint) {
        postMouseEvent(.mouseMoved, at: point, modifiers: [])
    }

    private func postMouseEvent(
        _ type: CGEventType,
        at point: CGPoint,
        modifiers: CGEventFlags
    ) {
        guard let event = CGEvent(
            mouseEventSource: nil,
            mouseType: type,
            mouseCursorPosition: point,
            mouseButton: .left
        ) else { return }
        event.flags = modifiers
        event.post(tap: .cghidEventTap)
    }
}
