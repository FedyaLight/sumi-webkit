import Foundation
import XCTest

/// End-to-end oracle for the durable session boundary. A fresh, pinned store
/// family and an explicit window snapshot must restore the exact space and
/// regular tab, then physically load that tab's local document in WebKit.
@MainActor
final class SumiSessionRestoreUITests: SumiLaunchSmokeUITestCase {
    func testRestoresExactWindowSpaceTabAndLocalDocument() throws {
        let restored = try prepareRestoreFixture()
        let app = try launchApp(preferencesHomeURL: restored.preferencesHomeURL)
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(
            window.waitForExistence(timeout: 5),
            "Restored browser window is missing"
        )

        let spaceTitle = element(
            withIdentifier: "space-title-\(restored.sidebar.personalSpaceID)",
            in: app
        )
        XCTAssertTrue(
            spaceTitle.waitForExistence(timeout: 10),
            "The persisted current space was not restored"
        )

        let selectedTab = app.buttons.matching(
            identifier: "tab-row-\(restored.sidebar.regularTabID)"
        ).firstMatch
        XCTAssertTrue(selectedTab.waitForExistence(timeout: 10), "The persisted current tab is missing")
        wait(
            for: NSPredicate(format: "value == %@", "selected"),
            on: selectedTab,
            timeout: 10,
            message: "The persisted current tab was not selected"
        )

        let siblingTab = element(
            withIdentifier: "space-regular-tab-\(restored.sidebar.secondaryRegularTabID)",
            in: app
        )
        XCTAssertTrue(
            siblingTab.waitForExistence(timeout: 10),
            "The structural tab store was not restored alongside the active selection"
        )

        let urlBar = app.staticTexts.matching(identifier: "sidebar-urlbar").firstMatch
        XCTAssertTrue(urlBar.waitForExistence(timeout: 10), "Sidebar URL bar is missing")
        wait(
            for: NSPredicate(format: "value == %@", restored.pageURLString),
            on: urlBar,
            timeout: 30,
            message: "The restored tab does not expose its exact persisted URL"
        )

        let renderedMarker = window.descendants(matching: .any).matching(
            NSPredicate(
                format: "value == %@ OR label == %@",
                restored.bodyMarker,
                restored.bodyMarker
            )
        ).firstMatch
        wait(
            for: NSPredicate(format: "exists == true"),
            on: renderedMarker,
            timeout: 30,
            message: "The restored local document never rendered in WebKit"
        )
    }

    func testRestoresLiveLauncherAtContinuedURLAndRendersDocument() throws {
        let restored = try prepareLiveLauncherRestoreFixture()
        let app = try launchApp(preferencesHomeURL: restored.preferencesHomeURL)
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(
            window.waitForExistence(timeout: 5),
            "Restored browser window is missing"
        )

        let launcher = element(
            withIdentifier: "space-pinned-shortcut-\(restored.launcherID)",
            in: app
        )
        XCTAssertTrue(
            launcher.waitForExistence(timeout: 10),
            "The restored launcher is missing"
        )

        let urlBar = app.staticTexts.matching(
            identifier: "sidebar-urlbar"
        ).firstMatch
        XCTAssertTrue(
            urlBar.waitForExistence(timeout: 10),
            "Sidebar URL bar is missing"
        )
        wait(
            for: NSPredicate(format: "value == %@", restored.currentURLString),
            on: urlBar,
            timeout: 30,
            message: "The launcher did not resume its persisted current URL"
        )

        let renderedMarker = window.descendants(matching: .any).matching(
            NSPredicate(
                format: "value == %@ OR label == %@",
                restored.bodyMarker,
                restored.bodyMarker
            )
        ).firstMatch
        wait(
            for: NSPredicate(format: "exists == true"),
            on: renderedMarker,
            timeout: 30,
            message: "The restored launcher URL never rendered in WebKit"
        )
    }

    private struct RestoreFixture {
        let preferencesHomeURL: URL
        let sidebar: PersonalSidebarFixture
        let pageURLString: String
        let bodyMarker: String
    }

    private struct LiveLauncherRestoreFixture {
        let preferencesHomeURL: URL
        let launcherID: String
        let currentURLString: String
        let bodyMarker: String
    }

    private func prepareRestoreFixture() throws -> RestoreFixture {
        let sidebar = try loadPersonalSidebarFixture()
        let token = UUID().uuidString.prefix(8)
        let bodyMarker = "SUMI-SESSION-RESTORE-ORACLE-\(token)"
        let pageDirectory = try makeSmokeScratchDirectory(prefix: "SumiSessionRestoreFixture")
        smokeAppSupportDirectories.append(pageDirectory)
        let pageURL = pageDirectory
            .appendingPathComponent("session-restore-\(token).html", isDirectory: false)
            .resolvingSymlinksInPath()
        let html = """
        <!DOCTYPE html>
        <html>
        <head><meta charset="utf-8"><title>Sumi Session Restore Oracle</title></head>
        <body><h1>\(bodyMarker)</h1></body>
        </html>
        """
        try html.write(to: pageURL, atomically: true, encoding: .utf8)
        let pageURLString = pageURL.absoluteString

        let preferencesHomeURL = try prepareSelectedRegularTabPreferencesHome(
            tabURLString: pageURLString,
            tabName: "Session Restore Oracle"
        )

        return RestoreFixture(
            preferencesHomeURL: preferencesHomeURL,
            sidebar: sidebar,
            pageURLString: pageURLString,
            bodyMarker: bodyMarker
        )
    }

    private func prepareLiveLauncherRestoreFixture() throws
        -> LiveLauncherRestoreFixture {
        let sidebar = try loadPersonalSidebarFixture()
        let launcherID = try XCTUnwrap(sidebar.topLevelLauncherID)
        let token = UUID().uuidString.prefix(8)
        let pageDirectory = try makeSmokeScratchDirectory(
            prefix: "SumiLauncherSessionRestoreFixture"
        )
        smokeAppSupportDirectories.append(pageDirectory)

        let bodyMarker = "SUMI-LAUNCHER-SESSION-RESTORE-ORACLE-\(token)"
        let currentURL = pageDirectory
            .appendingPathComponent("continued-\(token).html", isDirectory: false)
            .resolvingSymlinksInPath()
        try "<html><body><h1>\(bodyMarker)</h1></body></html>".write(
            to: currentURL,
            atomically: true,
            encoding: .utf8
        )

        let profileID = try accessibilityUUIDString(fromHex: sidebar.profileID)
        let snapshot: [String: Any] = [
            "currentTabId": UUID().uuidString,
            "currentSpaceId": sidebar.personalSpaceID,
            "currentProfileId": profileID,
            "activeShortcutPinId": launcherID,
            "activeShortcutPinRole": "spacePinned",
            "isShowingEmptyState": false,
            "activeTabsBySpace": [],
            "activeShortcutsBySpace": [[
                "spaceId": sidebar.personalSpaceID,
                "shortcutPinId": launcherID,
            ]],
            "liveShortcuts": [[
                "shortcutPinId": launcherID,
                "presentationSpaceId": sidebar.personalSpaceID,
                "currentURL": currentURL.absoluteString,
                "title": "Continued Launcher",
            ]],
            "collapsedPinnedSpaceIDs": [],
            "sidebarWidth": 250.0,
            "savedSidebarWidth": 250.0,
            "sidebarContentWidth": 234.0,
            "isSidebarVisible": true,
            "commandPaletteDraft": [
                "text": "",
                "navigateCurrentTab": false,
            ],
        ]
        let snapshotData = try JSONSerialization.data(
            withJSONObject: snapshot,
            options: []
        )
        let preferencesHomeURL = try preparePreferencesHome(
            windowSessionSnapshotData: snapshotData
        )

        return LiveLauncherRestoreFixture(
            preferencesHomeURL: preferencesHomeURL,
            launcherID: launcherID,
            currentURLString: currentURL.absoluteString,
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
