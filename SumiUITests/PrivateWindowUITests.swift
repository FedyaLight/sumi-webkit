import AppKit
import Foundation
import XCTest

@MainActor
final class PrivateWindowUITests: SumiLaunchSmokeUITestCase {
    func testPrivateWindowLoadsAPage() throws {
        let token = UUID().uuidString.prefix(8)
        let bodyMarker = "SUMI-PRIVATE-ORACLE-\(token)"
        let server = try SumiUIOracleHTTPServer(
            path: "private-\(token).html",
            html: """
            <!DOCTYPE html>
            <html><head><meta charset="utf-8"><title>Private Oracle \(token)</title></head>
            <body><h1 id="result">\(bodyMarker)</h1></body></html>
            """
        )
        defer { server.stop() }

        let app = try launchApp(
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
        let firstWindow = app.windows.element(boundBy: 0)
        XCTAssertTrue(firstWindow.waitForExistence(timeout: 20), "No browser window appeared")

        app.menuBars.menuBarItems["File"].click()
        let privateItem = app.menuItems["New Private Window"].firstMatch
        XCTAssertTrue(privateItem.waitForExistence(timeout: 5), "No private window menu item")
        privateItem.click()

        let deadline = Date().addingTimeInterval(15)
        while app.windows.count < 2, Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        let privateWindow = app.windows["Private Window - Sumi"].firstMatch
        XCTAssertTrue(
            privateWindow.waitForExistence(timeout: 5),
            "The private window does not use its private title"
        )

        XCTAssertTrue(
            waitForCommandPalette(in: app, timeout: 15),
            "URL Hub did not appear in the private window"
        )

        let input = element(withIdentifier: "command-palette-input", in: app)
        XCTAssertTrue(input.waitForExistence(timeout: 5), "No URL Hub input")
        try pasteText(server.pageURL.absoluteString, into: input, in: app)
        wait(
            for: NSPredicate(format: "value == %@", server.pageURL.absoluteString),
            on: input,
            timeout: 10,
            message: "URL Hub did not receive the URL; value: \(String(describing: input.value))"
        )
        input.typeKey(.return, modifierFlags: [])

        let renderedDocument = privateWindow.descendants(matching: .any).matching(
            NSPredicate(format: "value == %@ OR label == %@", bodyMarker, bodyMarker)
        ).firstMatch
        let rendered = renderedDocument.waitForExistence(timeout: 25)
        XCTAssertTrue(rendered, "The private window never rendered the fixture page")
    }
}
