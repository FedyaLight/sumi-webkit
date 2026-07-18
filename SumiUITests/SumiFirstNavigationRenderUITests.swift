import AppKit
import Carbon
import Foundation
import XCTest

/// Verifies that the first browser-owned HTTP navigation both loads and paints
/// without requiring a reload. The loopback fixture exercises the GPC rewrite
/// path without depending on external network state.
@MainActor
final class SumiFirstNavigationRenderUITests: SumiLaunchSmokeUITestCase {
    func testFirstHTTPNavigationRendersWithoutReload() throws {
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
            <body><h1>\(bodyMarker)</h1></body>
            </html>
            """
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
            preferencesHomeURL: try prepareSmokePreferencesHome(),
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 10), "The browser window did not appear")

        app.typeKey("t", modifierFlags: [.command])
        XCTAssertTrue(
            waitForFloatingBar(in: app, timeout: 10),
            "URL Hub did not appear for the first navigation"
        )
        let input = element(withIdentifier: "floating-bar-input", in: app)
        XCTAssertTrue(input.isHittable, "URL Hub input is not hittable")
        try paste(server.pageURL.absoluteString, into: input, in: app)
        wait(
            for: NSPredicate(format: "value == %@", server.pageURL.absoluteString),
            on: input,
            timeout: 10,
            message: "URL Hub did not receive the loopback fixture URL; value: \(String(describing: input.value))"
        )
        app.typeKey(.return, modifierFlags: [])
        wait(
            for: NSPredicate(format: "exists == false"),
            on: element(withIdentifier: "floating-bar-input", in: app),
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

    private func paste(
        _ text: String,
        into input: XCUIElement,
        in app: XCUIApplication
    ) throws {
        let pasteboard = NSPasteboard.general
        let previousContents: [(type: NSPasteboard.PasteboardType, data: Data)] =
            pasteboard.types?.compactMap { type in
                pasteboard.data(forType: type).map { (type, $0) }
            } ?? []
        defer {
            pasteboard.clearContents()
            if previousContents.isEmpty == false {
                pasteboard.declareTypes(previousContents.map(\.type), owner: nil)
                for content in previousContents {
                    pasteboard.setData(content.data, forType: content.type)
                }
            }
        }

        pasteboard.clearContents()
        guard pasteboard.setString(text, forType: .string) else {
            throw FixtureError.missingValue("Unable to seed the pasteboard with the fixture URL")
        }
        input.click()
        app.typeKey("v", modifierFlags: [.command])
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
