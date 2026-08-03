import Foundation
import XCTest

/// End-to-end oracles for browser-owned native UI triggered by loopback pages.
@MainActor
final class SumiPermissionPromptUITests: SumiLaunchSmokeUITestCase {
    func testUserActivatedFileInputPresentsSystemOpenPanel() throws {
        let buttonLabel = "Add photo"
        let server = try SumiUIOracleHTTPServer(
            path: "file-picker-oracle.html",
            html: """
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"><title>File Picker Oracle</title></head>
            <body>
              <button type="button" onclick="document.getElementById('photo').click()">
                \(buttonLabel)
              </button>
              <input id="photo" type="file" accept="image/*" hidden>
            </body>
            </html>
            """
        )
        defer { server.stop() }

        let preferencesHomeURL = try prepareSelectedRegularTabPreferencesHome(
            tabURLString: server.pageURL.absoluteString,
            tabName: "File Picker UI Oracle"
        )
        let app = try launchApp(
            preferencesHomeURL: preferencesHomeURL,
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
        let browserWindow = app.windows.element(boundBy: 0)
        XCTAssertTrue(browserWindow.waitForExistence(timeout: 10), "The browser window did not appear")

        let addPhotoButton = browserWindow.buttons[buttonLabel]
        wait(
            for: NSPredicate(format: "exists == true AND hittable == true"),
            on: addPhotoButton,
            timeout: 20,
            message: "The file input trigger did not render"
        )
        addPhotoButton.click()

        let openPanel = app.sheets.firstMatch
        XCTAssertTrue(
            openPanel.waitForExistence(timeout: 5),
            "A user-activated HTML file input did not present the system open panel"
        )
        openPanel.buttons["Cancel"].click()
    }

    func testExternalSchemePermissionPromptCanDenyWithoutLeavingPage() throws {
        let token = UUID().uuidString.prefix(8)
        let bodyMarker = "SUMI-PERMISSION-ORACLE-\(token)"
        let linkLabel = "Request external app permission"
        let server = try SumiUIOracleHTTPServer(
            path: "permission-oracle.html",
            html: """
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"><title>Sumi Permission Oracle</title></head>
            <body>
              <h1>\(bodyMarker)</h1>
              <a href="mailto:sumi-ui-oracle@example.invalid">\(linkLabel)</a>
            </body>
            </html>
            """
        )
        defer { server.stop() }

        let preferencesHomeURL = try prepareSelectedRegularTabPreferencesHome(
            tabURLString: server.pageURL.absoluteString,
            tabName: "Permission UI Oracle"
        )
        let app = try launchApp(
            preferencesHomeURL: preferencesHomeURL,
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
        let browserWindow = app.windows.element(boundBy: 0)
        XCTAssertTrue(browserWindow.waitForExistence(timeout: 10), "The browser window did not appear")

        let pageMarker = renderedElement(label: bodyMarker, in: browserWindow)
        wait(
            for: NSPredicate(format: "exists == true"),
            on: pageMarker,
            timeout: 20,
            message: "The loopback permission fixture did not render"
        )
        let permissionLink = renderedElement(label: linkLabel, in: browserWindow)
        wait(
            for: NSPredicate(format: "exists == true AND hittable == true"),
            on: permissionLink,
            timeout: 10,
            message: "The user-activated external-scheme link is not available"
        )
        permissionLink.click()

        let prompt = element(withIdentifier: "permission-authorization-popover", in: app)
        wait(
            for: NSPredicate(format: "exists == true"),
            on: prompt,
            timeout: 10,
            message: "Sumi did not present its permission authorization popover"
        )
        XCTAssertTrue(
            prompt.label.localizedCaseInsensitiveContains("wants to open"),
            "The visible permission prompt is not the requested external-app decision"
        )
        let deny = app.buttons["Don't allow"]
        XCTAssertTrue(deny.waitForExistence(timeout: 5), "The permission prompt has no deny action")
        deny.click()

        wait(
            for: NSPredicate(format: "exists == false"),
            on: prompt,
            timeout: 10,
            message: "The permission prompt did not settle after denial"
        )
        XCTAssertTrue(pageMarker.exists, "Denying the external scheme navigated away from the source page")

        let expectedHost = try XCTUnwrap(server.pageURL.host)
        let urlBar = app.staticTexts.matching(identifier: "sidebar-urlbar").firstMatch
        wait(
            for: NSPredicate(format: "value == %@", expectedHost),
            on: urlBar,
            timeout: 10,
            message: "Denying the permission changed the visible active-page host"
        )
    }

    private func renderedElement(
        label: String,
        in root: XCUIElement
    ) -> XCUIElement {
        root.descendants(matching: .any).matching(
            NSPredicate(format: "value == %@ OR label == %@", label, label)
        ).firstMatch
    }

    private func wait(
        for predicate: NSPredicate,
        on element: XCUIElement,
        timeout: TimeInterval,
        message: @autoclosure () -> String
    ) {
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        XCTAssertEqual(
            XCTWaiter().wait(for: [expectation], timeout: timeout),
            .completed,
            message()
        )
    }
}
