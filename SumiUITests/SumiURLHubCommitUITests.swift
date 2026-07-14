import Foundation
import XCTest

/// End-to-end oracle for the URL Hub (floating bar) commit contract: opening
/// the hub with the standard keyboard command, typing a destination, and
/// confirming with Return must navigate the active tab to exactly that
/// destination. The destination is a local `file://` fixture page, so the
/// test proves a real page load without any network dependency.
@MainActor
final class SumiURLHubCommitUITests: SumiLaunchSmokeUITestCase {
    private struct LocalPageFixture {
        let urlString: String
        let bodyMarker: String
    }

    func testURLHubCommitNavigatesActiveTabToLocalFixturePage() throws {
        let fixture = try prepareLocalPageFixture()
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(
            waitForFloatingBar(in: app, timeout: 10),
            "URL Hub (floating bar) did not appear after Cmd+T"
        )

        let input = element(withIdentifier: "floating-bar-input", in: app)
        XCTAssertTrue(input.exists, "URL Hub input is missing from the hub surface")
        XCTAssertTrue(input.isHittable, "URL Hub input is not hittable")

        // Type without clicking: the characters landing in the input proves
        // the hub received keyboard focus as part of its standard opening.
        app.typeText(fixture.urlString)
        // Accessibility snapshots stall for several seconds while the smoke
        // theme animates, so waits need generous ceilings; the expectation
        // still completes as soon as the predicate matches.
        wait(
            for: NSPredicate(format: "value == %@", fixture.urlString),
            on: input,
            timeout: 20,
            message: "URL Hub input did not receive the typed fixture URL; value: \(String(describing: input.value))"
        )

        app.typeKey(.return, modifierFlags: [])

        // The hub must dismiss after a successful commit.
        wait(
            for: NSPredicate(format: "exists == false"),
            on: element(withIdentifier: "floating-bar-input", in: app),
            timeout: 20,
            message: "URL Hub did not dismiss after committing with Return"
        )

        // The active tab must display exactly the committed URL. The URL bar
        // renders file URLs verbatim, so an exact value match rules out a
        // wrong tab, a search fallback, or a commit that never navigated.
        let urlBar = app.staticTexts.matching(identifier: "sidebar-urlbar").firstMatch
        XCTAssertTrue(urlBar.waitForExistence(timeout: 10), "Sidebar URL bar is missing")
        wait(
            for: NSPredicate(format: "value == %@", fixture.urlString),
            on: urlBar,
            timeout: 30,
            message: "URL bar does not show the committed fixture URL \(fixture.urlString); "
                + "url bar element: \(urlBar.debugDescription)"
        )

        // The fixture page must have actually loaded: its unique body marker
        // is only observable when WebKit rendered the local document. The
        // heading is matched as `.any` because WebKit exposes it with an
        // automation type XCUITest does not map cleanly onto StaticText.
        let renderedMarker = window.descendants(matching: .any).matching(
            NSPredicate(format: "value == %@ OR label == %@", fixture.bodyMarker, fixture.bodyMarker)
        ).firstMatch
        wait(
            for: NSPredicate(format: "exists == true"),
            on: renderedMarker,
            timeout: 30,
            message: "Fixture page body marker \(fixture.bodyMarker) never appeared; the committed URL did not load"
        )
    }

    private func prepareLocalPageFixture() throws -> LocalPageFixture {
        let token = UUID().uuidString.prefix(8)
        let pageTitle = "Sumi URL Hub Oracle \(token)"
        let bodyMarker = "SUMI-URL-HUB-ORACLE-\(token)"
        let directory = try makeSmokeScratchDirectory(prefix: "SumiURLHubFixture")
        smokeAppSupportDirectories.append(directory)

        let pageURL = directory
            .appendingPathComponent("url-hub-oracle-\(token).html", isDirectory: false)
            .resolvingSymlinksInPath()
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>\(pageTitle)</title></head>
        <body><h1>\(bodyMarker)</h1></body>
        </html>
        """
        try html.write(to: pageURL, atomically: true, encoding: .utf8)

        return LocalPageFixture(
            urlString: pageURL.absoluteString,
            bodyMarker: bodyMarker
        )
    }

    private func wait(
        for predicate: NSPredicate,
        on element: XCUIElement,
        timeout: TimeInterval,
        message: @autoclosure () -> String
    ) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        let result = XCTWaiter().wait(for: [expectation], timeout: timeout)
        XCTAssertEqual(result, .completed, message())
    }
}
