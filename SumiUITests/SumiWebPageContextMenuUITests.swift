import AppKit
import Foundation
import XCTest

/// End-to-end checks for webpage context-menu commands that cross from the
/// WebKit menu into Sumi-owned browser behavior.
@MainActor
final class SumiWebPageContextMenuUITests: SumiLaunchSmokeUITestCase {
    func testPageNavigationActionsMoveHistoryAndReload() throws {
        let targetMarker = "Context navigation target"
        let targetBackgroundLabel = "Target page background"
        let targetServer = try SumiUIOracleHTTPServer(
            path: "context-navigation-target.html",
            html: """
            <!DOCTYPE html>
            <html><body>
              <h1>\(targetMarker)</h1>
              <div role="img" aria-label="\(targetBackgroundLabel)"
                   style="width:240px;height:100px;background:#ddd"></div>
              <div id="load-count"></div>
              <script>
                const key = 'sumi-context-navigation-loads';
                const count = Number(sessionStorage.getItem(key) || '0') + 1;
                sessionStorage.setItem(key, String(count));
                document.getElementById('load-count').setAttribute(
                  'aria-label', `Target load ${count}`
                );
              </script>
            </body></html>
            """
        )
        defer { targetServer.stop() }

        let sourceMarker = "Context navigation source"
        let sourceBackgroundLabel = "Source page background"
        let linkLabel = "Navigate to context target"
        let sourceServer = try SumiUIOracleHTTPServer(
            path: "context-navigation-source.html",
            html: """
            <!DOCTYPE html>
            <html><body>
              <h1>\(sourceMarker)</h1>
              <div role="img" aria-label="\(sourceBackgroundLabel)"
                   style="width:240px;height:100px;background:#eee"></div>
              <a href="\(targetServer.pageURL.absoluteString)">\(linkLabel)</a>
            </body></html>
            """
        )
        defer { sourceServer.stop() }

        let preferencesHomeURL = try prepareSelectedRegularTabPreferencesHome(
            tabURLString: sourceServer.pageURL.absoluteString,
            tabName: "Context Navigation"
        )
        let app = try launchApp(
            preferencesHomeURL: preferencesHomeURL,
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(renderedElement(label: sourceMarker, in: window).waitForExistence(timeout: 20))

        window.links[linkLabel].click()
        XCTAssertTrue(renderedElement(label: targetMarker, in: window).waitForExistence(timeout: 20))
        chooseMenuItem(
            "Back",
            identifier: "SumiWebPageMenu.Back",
            from: window.images[targetBackgroundLabel],
            app: app
        )
        XCTAssertTrue(renderedElement(label: sourceMarker, in: window).waitForExistence(timeout: 20))

        chooseMenuItem(
            "Forward",
            identifier: "SumiWebPageMenu.Forward",
            from: window.images[sourceBackgroundLabel],
            app: app
        )
        XCTAssertTrue(renderedElement(label: targetMarker, in: window).waitForExistence(timeout: 20))

        let loadMarkers = window.descendants(matching: .any).matching(
            NSPredicate(format: "label BEGINSWITH 'Target load '")
        )
        let currentLoadMarker = loadMarkers.firstMatch
        XCTAssertTrue(currentLoadMarker.waitForExistence(timeout: 10))
        let currentLoadLabel = currentLoadMarker.label
        chooseMenuItem(
            "Reload",
            identifier: "SumiWebPageMenu.Reload",
            from: window.images[targetBackgroundLabel],
            app: app
        )
        let reloadedMarker = window.descendants(matching: .any).matching(
            NSPredicate(
                format: "label BEGINSWITH 'Target load ' AND label != %@",
                currentLoadLabel
            )
        ).firstMatch
        XCTAssertTrue(
            reloadedMarker.waitForExistence(timeout: 20),
            "Reload did not execute a fresh page load"
        )
    }

    func testPageLinkImageAndEmailActionsReachExpectedSystemBehavior() throws {
        let imageContents = """
        <svg xmlns="http://www.w3.org/2000/svg" width="120" height="80">
          <rect width="120" height="80" fill="#ff4f64"/>
        </svg>
        """
        let imageServer = try SumiUIOracleHTTPServer(
            path: "copy-image.svg",
            html: imageContents,
            contentType: "image/svg+xml"
        )
        defer { imageServer.stop() }
        let pageMarker = "Context menu page marker"
        let pageBackgroundLabel = "Page background target"
        let linkLabel = "Context link"
        let emailLabel = "Context email"
        let imageLabel = "Context image"
        let targetURL = "https://example.com/context-target"
        let pageServer = try SumiUIOracleHTTPServer(
            path: "context-actions.html",
            html: """
            <!DOCTYPE html>
            <html><body>
              <h1>\(pageMarker)</h1>
              <div role="img" aria-label="\(pageBackgroundLabel)"
                   style="width:240px;height:100px;background:#eee"></div>
              <a href="\(targetURL)" style="display:block;width:220px;height:32px">\(linkLabel)</a>
              <a href="mailto:a@example.com,b@example.com"
                 style="display:block;width:220px;height:32px">\(emailLabel)</a>
              <img src="\(imageServer.pageURL.absoluteString)" alt="\(imageLabel)"
                   width="120" height="80">
            </body></html>
            """
        )
        defer { pageServer.stop() }
        let preferencesHomeURL = try prepareSelectedRegularTabPreferencesHome(
            tabURLString: pageServer.pageURL.absoluteString,
            tabName: "Context Menu Actions"
        )
        let app = try launchApp(
            preferencesHomeURL: preferencesHomeURL,
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        XCTAssertTrue(renderedElement(label: pageMarker, in: window).waitForExistence(timeout: 20))
        let pageBackground = window.images[pageBackgroundLabel]
        let link = window.links[linkLabel]
        let email = window.links[emailLabel]
        let image = window.images[imageLabel]

        assertCopiedString(
            pageServer.pageURL.absoluteString,
            from: pageBackground,
            menuItemTitle: "Copy Page Address",
            app: app
        )
        assertCopiedString(
            targetURL,
            from: link,
            menuItemTitle: "Copy Link",
            app: app
        )
        assertCopiedString(
            "a@example.com, b@example.com",
            from: email,
            menuItemTitle: "Copy Email Addresses",
            app: app
        )
        assertCopiedString(
            imageServer.pageURL.absoluteString,
            from: image,
            menuItemTitle: "Copy Image Address",
            app: app
        )

        NSPasteboard.general.clearContents()
        chooseMenuItem("Copy Image", from: image, app: app)
        XCTAssertTrue(
            waitForImageOnPasteboard(),
            "Native Copy Image did not place image data on the pasteboard"
        )

        chooseMenuItem("Bookmark This Page…", from: pageBackground, app: app)
        XCTAssertTrue(
            app.staticTexts["Add bookmark"].waitForExistence(timeout: 5),
            "Bookmark Page did not present the bookmark editor"
        )
        app.typeKey(.escape, modifierFlags: [])

        chooseMenuItem("Print Page…", from: pageBackground, app: app)
        let printPanel = app.sheets.firstMatch
        XCTAssertTrue(
            printPanel.waitForExistence(timeout: 8),
            "Print Page… did not present the system print panel"
        )
        printPanel.buttons["Cancel"].click()

    }

    func testInspectElementOpensWebInspector() throws {
        let backgroundLabel = "Inspect context target"
        let server = try SumiUIOracleHTTPServer(
            path: "inspect-context-menu.html",
            html: """
            <!DOCTYPE html>
            <html><body>
              <div role="img" aria-label="\(backgroundLabel)"
                   style="position:fixed;left:20px;bottom:0;width:240px;height:100px;background:#eee"></div>
            </body></html>
            """
        )
        defer { server.stop() }

        let preferencesHomeURL = try prepareSelectedRegularTabPreferencesHome(
            tabURLString: server.pageURL.absoluteString,
            tabName: "Inspect Context Menu"
        )
        let app = try launchApp(
            preferencesHomeURL: preferencesHomeURL,
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 10))
        let background = window.images[backgroundLabel]
        wait(
            for: NSPredicate(format: "exists == true AND hittable == true"),
            on: background,
            timeout: 20,
            message: "The inspect context-menu target did not render"
        )

        let initialBottomEdge = background.frame.maxY
        background.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        let inspectElement = app.menuItems["Inspect Element"]
        XCTAssertTrue(
            inspectElement.waitForExistence(timeout: 5),
            "The page context menu did not expose Inspect Element"
        )
        XCTAssertTrue(inspectElement.isEnabled)
        inspectElement.click()

        let deadline = Date().addingTimeInterval(10)
        var didOpenInspector = false
        while Date() < deadline {
            if background.exists, background.frame.maxY < initialBottomEdge - 100 {
                didOpenInspector = true
                break
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        XCTAssertTrue(
            didOpenInspector,
            "Inspect Element did not open the docked Web Inspector"
        )
    }

    func testContextMenuDownloadsExactImageAndLinkedFile() throws {
        let imageContents = """
        <svg xmlns="http://www.w3.org/2000/svg" width="160" height="100">
          <rect width="160" height="100" fill="#ff4f64"/>
        </svg>
        """
        let imageServer = try SumiUIOracleHTTPServer(
            path: "context-image.svg",
            html: imageContents,
            contentType: "image/svg+xml"
        )
        defer { imageServer.stop() }

        let linkedFileContents = "Sumi linked-file context-menu oracle\n"
        let linkedFileServer = try SumiUIOracleHTTPServer(
            path: "context-file.txt",
            html: linkedFileContents,
            contentType: "text/plain; charset=utf-8"
        )
        defer { linkedFileServer.stop() }

        let imageLabel = "Sumi context image"
        let dataImageLabel = "Sumi data URL image"
        let blobImageLabel = "Sumi blob URL image"
        let linkLabel = "Download context file"
        let dataImageContents = """
        <svg xmlns="http://www.w3.org/2000/svg" width="80" height="80">
          <circle cx="40" cy="40" r="36" fill="#437dff"/>
        </svg>
        """
        let dataImageURL = "data:image/svg+xml;base64,\(Data(dataImageContents.utf8).base64EncodedString())"
        let blobImageContents = """
        <svg xmlns="http://www.w3.org/2000/svg" width="90" height="70">
          <path d="M5 65 L45 5 L85 65 Z" fill="#4ec98b"/>
        </svg>
        """
        let blobImageBase64 = Data(blobImageContents.utf8).base64EncodedString()
        let pageServer = try SumiUIOracleHTTPServer(
            path: "image-context-menu.html",
            html: """
            <!DOCTYPE html>
            <html>
            <head><meta charset="utf-8"><title>Image Context Menu Oracle</title></head>
            <body>
              <img src="\(imageServer.pageURL.absoluteString)" alt="\(imageLabel)"
                   width="160" height="100">
              <img src="\(dataImageURL)" alt="\(dataImageLabel)" width="80" height="80">
              <img id="blob-image" alt="\(blobImageLabel)" width="90" height="70">
              <a href="\(linkedFileServer.pageURL.absoluteString)">\(linkLabel)</a>
              <script>
                const bytes = Uint8Array.from(atob('\(blobImageBase64)'), value => value.charCodeAt(0));
                document.getElementById('blob-image').src = URL.createObjectURL(
                  new Blob([bytes], { type: 'image/svg+xml' })
                );
              </script>
            </body>
            </html>
            """
        )
        defer { pageServer.stop() }

        let preferencesHomeURL = try prepareSelectedRegularTabPreferencesHome(
            tabURLString: pageServer.pageURL.absoluteString,
            tabName: "Image Context Menu Oracle"
        )
        let app = try launchApp(
            preferencesHomeURL: preferencesHomeURL,
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
        let browserWindow = app.windows.element(boundBy: 0)
        XCTAssertTrue(browserWindow.waitForExistence(timeout: 10))
        let downloadsDirectory = try XCTUnwrap(smokeAppSupportURL)
            .appendingPathComponent("TestDownloads/SumiDownloads", isDirectory: true)
        assertImageCopied(from: browserWindow.images[dataImageLabel], app: app)
        assertImageCopied(from: browserWindow.images[blobImageLabel], app: app)
        try assertContextMenuDownload(
            from: browserWindow.images[imageLabel],
            menuItemTitle: "Save Image As…",
            expectedContents: Data(imageContents.utf8),
            downloadsDirectory: downloadsDirectory,
            app: app
        )
        try assertContextMenuDownload(
            from: browserWindow.links[linkLabel],
            menuItemTitle: "Download Linked File As…",
            expectedContents: Data(linkedFileContents.utf8),
            downloadsDirectory: downloadsDirectory,
            app: app
        )
        try assertContextMenuDownload(
            from: browserWindow.images[dataImageLabel],
            menuItemTitle: "Save Image As…",
            expectedContents: Data(dataImageContents.utf8),
            downloadsDirectory: downloadsDirectory,
            app: app
        )
        try assertContextMenuDownload(
            from: browserWindow.images[blobImageLabel],
            menuItemTitle: "Save Image As…",
            expectedContents: Data(blobImageContents.utf8),
            downloadsDirectory: downloadsDirectory,
            app: app
        )
    }

    private func assertContextMenuDownload(
        from element: XCUIElement,
        menuItemTitle: String,
        expectedContents: Data,
        downloadsDirectory: URL,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        wait(
            for: NSPredicate(format: "exists == true AND hittable == true"),
            on: element,
            timeout: 20,
            message: "The context-menu target did not render"
        )
        let existingFiles = Set(
            (try? FileManager.default.contentsOfDirectory(
                at: downloadsDirectory,
                includingPropertiesForKeys: nil
            )) ?? []
        )
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        let menuItem = app.menuItems[menuItemTitle]
        XCTAssertTrue(
            menuItem.waitForExistence(timeout: 5),
            "The context menu did not expose \(menuItemTitle)",
            file: file,
            line: line
        )
        menuItem.click()

        XCTAssertTrue(
            waitForDownloadedFile(
                matching: expectedContents,
                in: downloadsDirectory,
                excluding: existingFiles
            ),
            "The context-menu download did not finish with the expected contents",
            file: file,
            line: line
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

    private func assertCopiedString(
        _ expectedValue: String,
        from element: XCUIElement,
        menuItemTitle: String,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        NSPasteboard.general.clearContents()
        chooseMenuItem(menuItemTitle, from: element, app: app, file: file, line: line)
        XCTAssertEqual(
            NSPasteboard.general.string(forType: .string),
            expectedValue,
            file: file,
            line: line
        )
    }

    private func assertImageCopied(
        from element: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        NSPasteboard.general.clearContents()
        chooseMenuItem("Copy Image", from: element, app: app, file: file, line: line)
        XCTAssertTrue(
            waitForImageOnPasteboard(),
            "Copy Image did not place image data on the pasteboard",
            file: file,
            line: line
        )
    }

    private func chooseMenuItem(
        _ title: String,
        identifier: String? = nil,
        from element: XCUIElement,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        wait(
            for: NSPredicate(format: "exists == true AND hittable == true"),
            on: element,
            timeout: 20,
            message: "The context-menu target did not render"
        )
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        let menuItem = app.menuItems[identifier ?? title]
        XCTAssertTrue(
            menuItem.waitForExistence(timeout: 5),
            "The context menu did not expose \(title)",
            file: file,
            line: line
        )
        menuItem.click()
    }

    private func waitForDownloadedFile(
        matching expectedContents: Data,
        in directory: URL,
        excluding existingFiles: Set<URL>
    ) -> Bool {
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let currentFiles = Set(
                (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil
                )) ?? []
            )
            if currentFiles.subtracting(existingFiles).contains(where: {
                (try? Data(contentsOf: $0)) == expectedContents
            }) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

    private func waitForImageOnPasteboard() -> Bool {
        let deadline = Date().addingTimeInterval(5)
        while Date() < deadline {
            if NSImage(pasteboard: .general) != nil {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return false
    }

}
