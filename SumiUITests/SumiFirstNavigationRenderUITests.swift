import AppKit
import Carbon
import Foundation
import XCTest

/// Verifies that the first browser-owned HTTP navigation both loads and paints
/// without requiring a reload. The loopback fixture exercises the GPC rewrite
/// path without depending on external network state.
@MainActor
final class SumiFirstNavigationRenderUITests: SumiLaunchSmokeUITestCase {
    func testFirstHTTPNavigationRendersWithoutReloadWhenGPCEnabled() throws {
        let token = UUID().uuidString.prefix(8)
        let bodyMarker = "SUMI-FIRST-NAVIGATION-ORACLE-\(token)"
        let server = try SumiUIOracleHTTPServer(
            path: "first-navigation-\(token).html",
            html: """
            <!DOCTYPE html>
            <html>
            <head>
              <meta charset="utf-8">
              <title>Sumi First Navigation Oracle \(token)</title>
              <style>
                html, body {
                  width: 100%;
                  min-height: 100%;
                  margin: 0;
                  background: black;
                  color: white;
                }
                body {
                  display: grid;
                  place-items: center;
                  font: 700 32px system-ui;
                }
              </style>
            </head>
            <body>
              <h1 id="result"></h1>
              <script>
                document.getElementById("result").textContent =
                  navigator.globalPrivacyControl === true
                    ? "\(bodyMarker)"
                    : "GPC-DOM-SIGNAL-MISSING";
              </script>
            </body>
            </html>
            """,
            requiredRequestHeader: .init(field: "Sec-GPC", value: "1")
        )
        defer { server.stop() }

        let currentInputSource = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
        let previousInputSourceID = try XCTUnwrap(inputSourceID(currentInputSource))
        try selectInputSource(id: "com.apple.keylayout.ABC")
        defer {
            do {
                try selectInputSource(id: previousInputSourceID)
            } catch {
                XCTFail("Unable to restore input source \(previousInputSourceID): \(error)")
            }
        }

        let app = try launchApp(
            preferencesHomeURL: try prepareSmokePreferencesHome(
                additionalPreferences: ["settings.privacy.gpcEnabled": true]
            ),
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
            "URL Hub did not appear for the first navigation"
        )
        let input = element(withIdentifier: "command-palette-input", in: app)
        XCTAssertTrue(input.isHittable, "URL Hub input is not hittable")
        try pasteText(server.pageURL.absoluteString, into: input, in: app)
        wait(
            for: NSPredicate(format: "value == %@", server.pageURL.absoluteString),
            on: input,
            timeout: 10,
            message: "URL Hub did not receive the loopback fixture URL; value: \(String(describing: input.value))"
        )
        input.typeKey(.return, modifierFlags: [])
        wait(
            for: NSPredicate(format: "exists == false"),
            on: element(withIdentifier: "command-palette-input", in: app),
            timeout: 20,
            message: "URL Hub did not dismiss after the first navigation"
        )

        let expectedDisplayedHost = try XCTUnwrap(server.pageURL.host)
        let urlBar = app.staticTexts.matching(identifier: "sidebar-urlbar").firstMatch
        wait(
            for: NSPredicate(format: "value == %@", expectedDisplayedHost),
            on: urlBar,
            timeout: 20,
            message: "The first navigation did not reach the loopback fixture; url bar: \(urlBar.debugDescription)"
        )

        let renderedMarker = window.descendants(matching: .any).matching(
            NSPredicate(format: "value == %@ OR label == %@", bodyMarker, bodyMarker)
        ).firstMatch
        wait(
            for: NSPredicate(format: "exists == true"),
            on: renderedMarker,
            timeout: 30,
            message: "The first HTTP document did not load without a reload"
        )

        let renderedBlackRatio = try dominantBlackPixelRatio(in: window.screenshot())
        XCTAssertGreaterThan(
            renderedBlackRatio,
            0.5,
            "The first HTTP document loaded but remained visually blank; black ratio: \(renderedBlackRatio)"
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
        let sources = TISCreateInputSourceList(filter, false).takeRetainedValue()
            as! [TISInputSource]
        let source = try XCTUnwrap(sources.first)
        let status = TISSelectInputSource(source)
        guard status == noErr else {
            throw FixtureError.missingValue(
                "Unable to select input source \(id): OSStatus \(status)"
            )
        }

        let deadline = Date().addingTimeInterval(2)
        while Date() < deadline {
            let current = TISCopyCurrentKeyboardInputSource().takeRetainedValue()
            if inputSourceID(current) == id {
                return
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        throw FixtureError.missingValue("Input source \(id) did not become current")
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
