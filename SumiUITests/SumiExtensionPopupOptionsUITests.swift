import CryptoKit
import Foundation
import XCTest

/// End-to-end WebExtension oracle backed by a fresh browser-owned package and
/// persisted ExtensionEntity. The app receives no test-only runtime hook: it
/// discovers, loads, and presents the extension through its production startup
/// and action paths.
@MainActor
final class SumiExtensionPopupOptionsUITests: SumiLaunchSmokeUITestCase {
    private static let extensionID = "sumi-ui-oracle-extension"
    private static let extensionName = "Sumi UI Oracle Extension"
    private static let optionsWindowTitle = "Sumi UI Oracle Extension – Options"

    func testExtensionActionPopupRendersManagedPackagePage() throws {
        let fixture = try prepareExtensionFixture()
        defer { fixture.landingServer.stop() }
        let app = try launchExtensionFixture(fixture)
        let browserWindow = app.windows.element(boundBy: 0)
        XCTAssertTrue(browserWindow.waitForExistence(timeout: 10), "The browser window did not appear")

        let action = openExtensionHub(in: app, fixture: fixture)
        action.click()

        let marker = renderedMarker(fixture.popupMarker, in: app)
        wait(
            for: NSPredicate(format: "exists == true"),
            on: marker,
            timeout: 20,
            message: "The real extension action popup did not render its managed-package page"
        )

        app.typeKey(.escape, modifierFlags: [])
        wait(
            for: NSPredicate(format: "exists == false"),
            on: marker,
            timeout: 10,
            message: "The extension action popup did not dismiss with Escape"
        )
    }

    func testExtensionOptionsOpensExactManagedPackagePage() throws {
        let fixture = try prepareExtensionFixture()
        defer { fixture.landingServer.stop() }
        let app = try launchExtensionFixture(fixture)
        let browserWindow = app.windows.element(boundBy: 0)
        XCTAssertTrue(browserWindow.waitForExistence(timeout: 10), "The browser window did not appear")

        let action = openExtensionHub(in: app, fixture: fixture)
        action.rightClick()
        let options = app.menuItems["Options"]
        XCTAssertTrue(options.waitForExistence(timeout: 5), "The extension action menu has no Options command")
        options.click()

        let optionsWindow = app.windows[Self.optionsWindowTitle]
        XCTAssertTrue(
            optionsWindow.waitForExistence(timeout: 20),
            "The production options window was not presented for the exact extension"
        )
        let marker = renderedMarker(fixture.optionsMarker, in: optionsWindow)
        wait(
            for: NSPredicate(format: "exists == true"),
            on: marker,
            timeout: 20,
            message: "The options window did not render the exact managed-package page"
        )

        app.typeKey("w", modifierFlags: [.command])
        wait(
            for: NSPredicate(format: "exists == false"),
            on: optionsWindow,
            timeout: 10,
            message: "The extension options window did not close through the native window command"
        )
        XCTAssertTrue(browserWindow.exists, "Closing options unexpectedly closed the browser window")
    }

    private struct ExtensionFixture {
        let preferencesHomeURL: URL
        let landingServer: SumiUIOracleHTTPServer
        let landingMarker: String
        let popupMarker: String
        let optionsMarker: String
    }

    private func prepareExtensionFixture() throws -> ExtensionFixture {
        let storeURL = try requiredSmokeStoreURL()
        let token = UUID().uuidString.prefix(8)
        let landingMarker = "SUMI-EXTENSION-LANDING-ORACLE-\(token)"
        let popupMarker = "SUMI-EXTENSION-POPUP-ORACLE-\(token)"
        let optionsMarker = "SUMI-EXTENSION-OPTIONS-ORACLE-\(token)"
        let landingServer = try SumiUIOracleHTTPServer(
            path: "extension-oracle-landing.html",
            html: extensionPage(marker: landingMarker, title: "Landing Oracle")
        )

        let preferencesHomeURL = try prepareSelectedRegularTabPreferencesHome(
            tabURLString: landingServer.pageURL.absoluteString,
            tabName: "Extension UI Oracle",
            additionalPreferences: [
                "settings.modules.extensions.enabled": true,
            ]
        )

        let packageURL = preferencesHomeURL
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Application Support", isDirectory: true)
            .appendingPathComponent("com.sumi.browser", isDirectory: true)
            .appendingPathComponent("ExtensionPackageGenerations-v1", isDirectory: true)
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(
            at: packageURL,
            withIntermediateDirectories: true
        )

        let manifest: [String: Any] = [
            "manifest_version": 3,
            "name": Self.extensionName,
            "version": "1.0.0",
            "description": "Hermetic Sumi UI presentation oracle",
            "action": [
                "default_title": Self.extensionName,
                "default_popup": "popup.html",
            ],
            "options_page": "options.html",
            "permissions": [],
        ]
        let manifestData = try JSONSerialization.data(
            withJSONObject: manifest,
            options: [.sortedKeys]
        )
        try manifestData.write(
            to: packageURL.appendingPathComponent("manifest.json"),
            options: .atomic
        )
        try extensionPage(marker: popupMarker, title: "Popup Oracle").write(
            to: packageURL.appendingPathComponent("popup.html"),
            atomically: true,
            encoding: .utf8
        )
        try extensionPage(marker: optionsMarker, title: "Options Oracle").write(
            to: packageURL.appendingPathComponent("options.html"),
            atomically: true,
            encoding: .utf8
        )
        try insertExtensionRecord(
            storeURL: storeURL,
            packageURL: packageURL,
            manifestData: manifestData
        )
        return ExtensionFixture(
            preferencesHomeURL: preferencesHomeURL,
            landingServer: landingServer,
            landingMarker: landingMarker,
            popupMarker: popupMarker,
            optionsMarker: optionsMarker
        )
    }

    private func insertExtensionRecord(
        storeURL: URL,
        packageURL: URL,
        manifestData: Data
    ) throws {
        let entity = try nextPrimaryKeyInfo(
            entityName: "ExtensionEntity",
            storeURL: storeURL
        )
        let activationSummary: [String: Any] = [
            "matchPatternStrings": [],
            "broadScope": false,
            "hasContentScripts": false,
            "hasAction": true,
            "hasOptionsPage": true,
            "hasExtensionPages": true,
        ]
        let activationData = try JSONSerialization.data(
            withJSONObject: activationSummary,
            options: [.sortedKeys]
        )
        let manifestJSON = try XCTUnwrap(String(data: manifestData, encoding: .utf8))
        let activationJSON = try XCTUnwrap(String(data: activationData, encoding: .utf8))
        let packagePath = packageURL.standardizedFileURL.path
        let manifestFingerprint = sha256(manifestData)
        let sourceFingerprint = sha256(Data(packagePath.utf8))

        try executeSQLite(
            sql: """
            INSERT INTO ZEXTENSIONENTITY (
                Z_PK, Z_ENT, Z_OPT, ZBROADSCOPE, ZHASACTION, ZHASBACKGROUND,
                ZHASCONTENTSCRIPTS, ZHASEXTENSIONPAGES, ZHASOPTIONSPAGE,
                ZISENABLED, ZMANIFESTVERSION, ZINSTALLDATE, ZLASTUPDATEDATE,
                ZACTIVATIONSUMMARYJSON, ZBACKGROUNDMODELRAWVALUE,
                ZDEFAULTPOPUPPATH, ZEXTENSIONDESCRIPTION, ZICONPATH, ZID,
                ZINCOGNITOMODERAWVALUE, ZMANIFESTROOTFINGERPRINT,
                ZMANIFESTSNAPSHOTJSON, ZNAME, ZOPTIONSPAGEPATH, ZPACKAGEPATH,
                ZSOURCEBUNDLEPATH, ZSOURCEKINDRAWVALUE,
                ZSOURCEPATHFINGERPRINT, ZVERSION
            ) VALUES (
                \(entity.primaryKey), \(entity.entity), 1, 0, 1, 0,
                0, 1, 1, 1, 3, 0, 0,
                \(sqlString(activationJSON)), \(sqlString("none")),
                \(sqlString("popup.html")),
                \(sqlString("Hermetic Sumi UI presentation oracle")), NULL,
                \(sqlString(Self.extensionID)), \(sqlString("spanning")),
                \(sqlString(manifestFingerprint)), \(sqlString(manifestJSON)),
                \(sqlString(Self.extensionName)), \(sqlString("options.html")),
                \(sqlString(packagePath)), \(sqlString(packagePath)),
                \(sqlString("directory")), \(sqlString(sourceFingerprint)),
                \(sqlString("1.0.0"))
            );
            UPDATE Z_PRIMARYKEY
            SET Z_MAX = MAX(Z_MAX, \(entity.primaryKey))
            WHERE Z_NAME = 'ExtensionEntity';
            """,
            storeURL: storeURL
        )
    }

    private func launchExtensionFixture(
        _ fixture: ExtensionFixture
    ) throws -> XCUIApplication {
        try launchApp(
            preferencesHomeURL: fixture.preferencesHomeURL,
            additionalEnvironment: [
                "AppleLanguages": "(en)",
                "AppleLocale": "en_US",
            ]
        )
    }

    private func openExtensionHub(
        in app: XCUIApplication,
        fixture: ExtensionFixture
    ) -> XCUIElement {
        let marker = renderedMarker(fixture.landingMarker, in: app)
        wait(
            for: NSPredicate(format: "exists == true"),
            on: marker,
            timeout: 30,
            message: "The persisted extension oracle landing page did not render"
        )

        let siteControls = element(withIdentifier: "urlbar-site-controls-button", in: app)
        XCTAssertTrue(siteControls.waitForExistence(timeout: 20), "The Site Controls button is missing")
        siteControls.click()

        let action = app.buttons.matching(
            NSPredicate(format: "label == %@", Self.extensionName)
        ).firstMatch
        XCTAssertTrue(
            action.waitForExistence(timeout: 20),
            "The enabled extension did not reach the production action surface"
        )
        return action
    }

    private func renderedMarker(
        _ marker: String,
        in root: XCUIElement
    ) -> XCUIElement {
        root.descendants(matching: .any).matching(
            NSPredicate(format: "value == %@ OR label == %@", marker, marker)
        ).firstMatch
    }

    private func extensionPage(marker: String, title: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>\(title)</title></head>
        <body><h1>\(marker)</h1></body>
        </html>
        """
    }

    private func sha256(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
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
