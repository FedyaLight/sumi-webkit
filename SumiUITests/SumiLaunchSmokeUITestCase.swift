import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
class SumiLaunchSmokeUITestCase: XCTestCase {
    enum BrowserWindowControlIdentifiers {
        static let closeButton = "browser-window-close-button"
        static let minimizeButton = "browser-window-minimize-button"
        static let zoomButton = "browser-window-zoom-button"
    }

    enum SmokeUITiming {
        static let trafficLightHoverStabilityWindow: TimeInterval = 0.7
    }

    var expectedTrafficLightVisualDiameter: CGFloat {
        if #available(macOS 26.0, *) {
            return 14
        } else {
            return 12
        }
    }

    nonisolated(unsafe) var smokeAppSupportURL: URL?
    nonisolated(unsafe) var smokeAppSupportDirectories: [URL] = []
    nonisolated(unsafe) var sidebarDragMarkerURL: URL?
    let smokeWindowSessionOverrideFileName = "sumi-window-session-override.json"
    let smokeWindowSessionOverrideEnvironmentKey = "SUMI_WINDOW_SESSION_OVERRIDE_PATH"
    let smokeShortcutDriftPinEnvironmentKey = "SUMI_SIDEBAR_DRIFT_SHORTCUT_PIN_ID"
    let smokeShortcutDriftURLEnvironmentKey = "SUMI_SIDEBAR_DRIFT_URL"
    struct PersonalSidebarFixture {
        let personalSpaceID: String
        let profileID: String
        let topLevelLauncherID: String?
        let regularTabID: String
        let secondaryRegularTabID: String
        let folderID: String?
        let folderLauncherID: String?
        let essentialID: String?
    }

    enum FixtureError: LocalizedError {
        case sqliteFailure(String)
        case malformedJSON
        case missingValue(String)
        case screenshotFailure(String)

        var errorDescription: String? {
            switch self {
            case .sqliteFailure(let message):
                message
            case .malformedJSON:
                "sqlite3 returned malformed JSON"
            case .missingValue(let description):
                description
            case .screenshotFailure(let description):
                description
            }
        }
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        for directory in smokeAppSupportDirectories {
            try? FileManager.default.removeItem(at: directory)
        }
        smokeAppSupportDirectories.removeAll()
        smokeAppSupportURL = nil
        if let sidebarDragMarkerURL {
            try? FileManager.default.removeItem(at: sidebarDragMarkerURL)
        }
        sidebarDragMarkerURL = nil
        try super.tearDownWithError()
    }

    nonisolated func skipUnlessInteractionE2E() throws {
        let environmentKey = "SUMI_RUN_INTERACTION_E2E"
        guard ProcessInfo.processInfo.environment[environmentKey] == "1" else {
            throw XCTSkip("Interaction E2E is opt-in for SumiSmoke; set \(environmentKey)=1 to run these tests.")
        }
    }

    @MainActor
    func launchApp(
        preferencesHomeURL: URL? = nil,
        additionalEnvironment: [String: String] = [:]
    ) throws -> XCUIApplication {
        if smokeAppSupportURL == nil {
            _ = try prepareSmokeStoreURL()
        }
        let app = XCUIApplication()
        app.launchArguments.append("--uitest-smoke")
        app.launchArguments.append("--uitest-sidebar-drag-marker=\(sidebarDragMarkerFileURL().path)")
        // Keeps automatic downloads out of the real ~/Downloads so macOS TCC does not prompt every run.
        app.launchEnvironment["SUMI_TEST_DOWNLOADS_ISOLATION"] = "1"
        if let smokeAppSupportURL {
            app.launchEnvironment["SUMI_APP_SUPPORT_OVERRIDE"] = smokeAppSupportURL.path
        }
        let resolvedPreferencesHomeURL: URL?
        if let preferencesHomeURL {
            resolvedPreferencesHomeURL = preferencesHomeURL
        } else if smokeAppSupportURL != nil {
            resolvedPreferencesHomeURL = try prepareSmokePreferencesHome()
        } else {
            resolvedPreferencesHomeURL = nil
        }
        if let resolvedPreferencesHomeURL {
            app.launchEnvironment["CFFIXED_USER_HOME"] = resolvedPreferencesHomeURL.path
            app.launchEnvironment["HOME"] = resolvedPreferencesHomeURL.path
            app.launchEnvironment["__CFPREFERENCES_AVOID_DAEMON"] = "1"
            let windowSessionOverrideURL = resolvedPreferencesHomeURL
                .appendingPathComponent(smokeWindowSessionOverrideFileName, isDirectory: false)
            if FileManager.default.fileExists(atPath: windowSessionOverrideURL.path) {
                app.launchEnvironment[smokeWindowSessionOverrideEnvironmentKey] = windowSessionOverrideURL.path
            }
        }
        for (key, value) in additionalEnvironment {
            app.launchEnvironment[key] = value
        }
        app.launch()
        app.activate()
        return app
    }

    func sidebarDragMarkerFileURL() -> URL {
        if let sidebarDragMarkerURL {
            return sidebarDragMarkerURL
        }
        let markerDirectory = smokeAppSupportURL ?? URL(fileURLWithPath: "/tmp", isDirectory: true)
        let url = markerDirectory
            .appendingPathComponent("SumiSidebarDrag-\(UUID().uuidString).marker", isDirectory: false)
        sidebarDragMarkerURL = url
        return url
    }
}
