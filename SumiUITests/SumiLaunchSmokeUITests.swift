import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
final class SumiLaunchSmokeUITests: XCTestCase {
    private enum BrowserWindowControlIdentifiers {
        static let closeButton = "browser-window-close-button"
        static let minimizeButton = "browser-window-minimize-button"
        static let zoomButton = "browser-window-zoom-button"
    }

    private var smokeAppSupportURL: URL?
    private var smokeAppSupportDirectories: [URL] = []
    private var sidebarDragMarkerURL: URL?
    private let smokeWindowSessionOverrideFileName = "sumi-window-session-override.json"
    private let smokeWindowSessionOverrideEnvironmentKey = "SUMI_WINDOW_SESSION_OVERRIDE_PATH"
    private let smokeShortcutDriftPinEnvironmentKey = "SUMI_SIDEBAR_DRIFT_SHORTCUT_PIN_ID"
    private let smokeShortcutDriftURLEnvironmentKey = "SUMI_SIDEBAR_DRIFT_URL"

    private struct PersonalSidebarFixture {
        let personalSpaceID: String
        let profileID: String
        let topLevelLauncherID: String?
        let regularTabID: String
        let secondaryRegularTabID: String
        let folderID: String?
        let folderLauncherID: String?
        let essentialID: String?
    }

    private enum FixtureError: LocalizedError {
        case missingStore(String)
        case sqliteFailure(String)
        case malformedJSON
        case missingValue(String)
        case screenshotFailure(String)

        var errorDescription: String? {
            switch self {
            case .missingStore(let path):
                "Missing current-profile store at \(path)"
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
    }

    @MainActor
    private func launchApp(
        preferencesHomeURL: URL? = nil,
        additionalEnvironment: [String: String] = [:]
    ) -> XCUIApplication {
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
            do {
                resolvedPreferencesHomeURL = try prepareSmokePreferencesHome()
            } catch {
                XCTFail("Failed to prepare smoke preferences home: \(error.localizedDescription)")
                resolvedPreferencesHomeURL = nil
            }
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

    private func sidebarDragMarkerFileURL() -> URL {
        if let sidebarDragMarkerURL {
            return sidebarDragMarkerURL
        }
        let markerDirectory = smokeAppSupportURL ?? FileManager.default.temporaryDirectory
        let url = markerDirectory
            .appendingPathComponent("SumiSidebarDrag-\(UUID().uuidString).marker", isDirectory: false)
        sidebarDragMarkerURL = url
        return url
    }

    func testLaunchesMainWindow() {
        let app = launchApp()

        XCTAssertTrue(app.windows.element(boundBy: 0).waitForExistence(timeout: 5))
    }

    func testRendersSpaceSwitcherShell() {
        let app = launchApp()
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "space-icon-")
        let spaceIcons = app.descendants(matching: .any).matching(predicate)

        XCTAssertTrue(spaceIcons.firstMatch.waitForExistence(timeout: 5))
    }

    func testNativeTrafficLightsAreHittableInNormalWindow() {
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testCollapsedHoverSidebarKeepsNativeTrafficLightsHittable() {
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        toggleSidebarVisibility(app: app, window: window)
        revealHoverSidebar(in: window)

        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testCollapsedHoverSidebarTrafficLightsStayHittableAfterResize() {
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        toggleSidebarVisibility(app: app, window: window)
        revealHoverSidebar(in: window)
        assertNativeTrafficLightsHittable(in: app, window: window)

        let initialWidth = window.frame.width
        resizeWindow(window, horizontalOffset: -220)
        XCTAssertLessThan(window.frame.width, initialWidth - 40)

        revealHoverSidebar(in: window)
        assertNativeTrafficLightsHittable(in: app, window: window)

        resizeWindow(window, horizontalOffset: 220)
        XCTAssertGreaterThan(window.frame.width, initialWidth - 120)

        revealHoverSidebar(in: window)
        assertNativeTrafficLightsHittable(in: app, window: window)
    }

    func testLaunchWithPersistedBrightThemeDoesNotRenderDominantBlackWindow() throws {
        let preferencesHomeURL = try prepareStartupThemeSmokeFixture()
        let app = launchApp(preferencesHomeURL: preferencesHomeURL)
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let blackRatio = try dominantBlackPixelRatio(in: window.screenshot())
        XCTAssertLessThan(blackRatio, 0.35)
    }

    func testVisibleSidebarContextMenuCanBeReopenedAfterDismiss() {
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let spaceIcon = firstSpaceIcon(in: app)
        XCTAssertTrue(spaceIcon.waitForExistence(timeout: 5))

        openSidebarContextMenu(on: spaceIcon, expectedMenuItem: "Space Settings", app: app)
        dismissContextMenu(in: window, expectedMenuItem: "Space Settings", app: app)
        openSidebarContextMenu(on: spaceIcon, expectedMenuItem: "Space Settings", app: app)
    }

    func testCollapsedHoverSidebarContextMenuCanBeReopenedAfterDismiss() {
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        toggleSidebarVisibility(app: app, window: window)
        revealHoverSidebar(in: window)

        let spaceIcon = firstSpaceIcon(in: app)
        XCTAssertTrue(spaceIcon.waitForExistence(timeout: 5))

        openSidebarContextMenu(on: spaceIcon, expectedMenuItem: "Space Settings", app: app)
        dismissContextMenu(in: window, expectedMenuItem: "Space Settings", app: app)
        revealHoverSidebar(in: window)
        XCTAssertTrue(spaceIcon.waitForExistence(timeout: 5))
        openSidebarContextMenu(on: spaceIcon, expectedMenuItem: "Space Settings", app: app)
    }

    func testPersonalVisibleSidebarContextMenusCanBeReopenedAfterDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        if let topLevelLauncherID = fixture.topLevelLauncherID {
            exerciseContextMenuReopen(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                expectedMenuItem: "Edit Link…",
                app: app,
                window: window,
                collapsedSidebar: false
            )
            performLauncherDragNoOp(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                app: app,
                window: window,
                collapsedSidebar: false
            )
            exerciseContextMenuReopen(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                expectedMenuItem: "Edit Link…",
                app: app,
                window: window,
                collapsedSidebar: false
            )
            exerciseNewTabButtonAfterContextMenuDismiss(
                contextElementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                expectedMenuItem: "Edit Link…",
                fixture: fixture,
                app: app,
                window: window,
                collapsedSidebar: false
            )
        }

        exerciseContextMenuReopen(
            elementID: "space-regular-tab-\(fixture.regularTabID)",
            expectedMenuItem: "Copy Link",
            app: app,
            window: window,
            collapsedSidebar: false
        )
        exerciseNewTabButtonAfterContextMenuDismiss(
            contextElementID: "space-regular-tab-\(fixture.regularTabID)",
            expectedMenuItem: "Copy Link",
            fixture: fixture,
            app: app,
            window: window,
            collapsedSidebar: false
        )

        if let essentialID = fixture.essentialID {
            exerciseContextMenuReopen(
                elementID: "essential-shortcut-\(essentialID)",
                expectedMenuItem: "Remove from Essentials",
                app: app,
                window: window,
                collapsedSidebar: false
            )
        }

        if let folderID = fixture.folderID {
            exerciseContextMenuReopen(
                elementID: "folder-header-\(folderID)",
                expectedMenuItem: "Rename Folder",
                app: app,
                window: window,
                collapsedSidebar: false
            )
        }
        if fixture.folderID != nil, fixture.folderLauncherID != nil {
            ensureFolderExpanded(fixture, app: app, window: window, collapsedSidebar: false)
            exerciseContextMenuReopen(
                elementID: "folder-shortcut-\(fixture.folderLauncherID!)",
                expectedMenuItem: "Edit Link…",
                app: app,
                window: window,
                collapsedSidebar: false
            )
        }
    }

    func testPersonalCollapsedHoverSidebarContextMenusCanBeReopenedAfterDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        toggleSidebarVisibility(app: app, window: window)
        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: true)

        if let topLevelLauncherID = fixture.topLevelLauncherID {
            exerciseContextMenuReopen(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                expectedMenuItem: "Edit Link…",
                app: app,
                window: window,
                collapsedSidebar: true
            )
            performLauncherDragNoOp(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                app: app,
                window: window,
                collapsedSidebar: true
            )
            exerciseContextMenuReopen(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                expectedMenuItem: "Edit Link…",
                app: app,
                window: window,
                collapsedSidebar: true
            )
            exerciseNewTabButtonAfterContextMenuDismiss(
                contextElementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                expectedMenuItem: "Edit Link…",
                fixture: fixture,
                app: app,
                window: window,
                collapsedSidebar: true
            )
        }

        exerciseContextMenuReopen(
            elementID: "space-regular-tab-\(fixture.regularTabID)",
            expectedMenuItem: "Copy Link",
            app: app,
            window: window,
            collapsedSidebar: true
        )
        exerciseNewTabButtonAfterContextMenuDismiss(
            contextElementID: "space-regular-tab-\(fixture.regularTabID)",
            expectedMenuItem: "Copy Link",
            fixture: fixture,
            app: app,
            window: window,
            collapsedSidebar: true
        )

        if let essentialID = fixture.essentialID {
            exerciseContextMenuReopen(
                elementID: "essential-shortcut-\(essentialID)",
                expectedMenuItem: "Remove from Essentials",
                app: app,
                window: window,
                collapsedSidebar: true
            )
        }

        if let folderID = fixture.folderID {
            exerciseContextMenuReopen(
                elementID: "folder-header-\(folderID)",
                expectedMenuItem: "Rename Folder",
                app: app,
                window: window,
                collapsedSidebar: true
            )
        }
        if fixture.folderID != nil, fixture.folderLauncherID != nil {
            ensureFolderExpanded(fixture, app: app, window: window, collapsedSidebar: true)
            exerciseContextMenuReopen(
                elementID: "folder-shortcut-\(fixture.folderLauncherID!)",
                expectedMenuItem: "Edit Link…",
                app: app,
                window: window,
                collapsedSidebar: true
            )
        }
    }

    func testPersonalVisibleSidebarTransientActionsKeepSidebarInteractive() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Change Theme",
            transientIdentifier: "workspace-theme-picker-panel",
            app: app,
            window: window,
            collapsedSidebar: false,
            dismissTransient: dismissThemePicker
        )
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Change Icon",
            transientIdentifier: "emoji-picker-panel",
            app: app,
            window: window,
            collapsedSidebar: false,
            dismissTransient: dismissEmojiPicker
        )
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Space Settings",
            transientIdentifier: "space-edit-dialog",
            app: app,
            window: window,
            collapsedSidebar: false,
            dismissTransient: dismissSpaceSettingsDialog
        )
        if let topLevelLauncherID = fixture.topLevelLauncherID {
            exerciseTransientActionFlow(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                menuItem: "Edit Icon",
                transientIdentifier: "emoji-picker-panel",
                app: app,
                window: window,
                collapsedSidebar: false,
                dismissTransient: dismissEmojiPicker
            )
            exerciseTransientActionFlow(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                menuItem: "Edit Link…",
                transientIdentifier: "shortcut-link-editor-sheet",
                app: app,
                window: window,
                collapsedSidebar: false,
                dismissTransient: dismissShortcutLinkEditor
            )
            assertNewTabButtonOpensCommandPalette(
                fixture: fixture,
                app: app,
                window: window,
                collapsedSidebar: false
            )
        }
        if let folderID = fixture.folderID {
            exerciseTransientActionFlow(
                elementID: "folder-header-\(folderID)",
                menuItem: "Change Folder Icon…",
                transientIdentifier: "folder-icon-picker-sheet",
                app: app,
                window: window,
                collapsedSidebar: false,
                dismissTransient: dismissFolderIconPicker
            )
            assertNewTabButtonOpensCommandPalette(
                fixture: fixture,
                app: app,
                window: window,
                collapsedSidebar: false
            )
        }
        if fixture.folderID != nil, fixture.folderLauncherID != nil {
            ensureFolderExpanded(fixture, app: app, window: window, collapsedSidebar: false)
            exerciseTransientActionFlow(
                elementID: "folder-shortcut-\(fixture.folderLauncherID!)",
                menuItem: "Edit Link…",
                transientIdentifier: "shortcut-link-editor-sheet",
                app: app,
                window: window,
                collapsedSidebar: false,
                dismissTransient: dismissShortcutLinkEditor
            )
        }
    }

    func testPersonalCollapsedHoverSidebarTransientActionsKeepSidebarInteractive() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        toggleSidebarVisibility(app: app, window: window)
        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: true)
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Change Theme",
            transientIdentifier: "workspace-theme-picker-panel",
            app: app,
            window: window,
            collapsedSidebar: true,
            dismissTransient: dismissThemePicker
        )
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Change Icon",
            transientIdentifier: "emoji-picker-panel",
            app: app,
            window: window,
            collapsedSidebar: true,
            dismissTransient: dismissEmojiPicker
        )
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Space Settings",
            transientIdentifier: "space-edit-dialog",
            app: app,
            window: window,
            collapsedSidebar: true,
            dismissTransient: dismissSpaceSettingsDialog
        )
        if let topLevelLauncherID = fixture.topLevelLauncherID {
            exerciseTransientActionFlow(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                menuItem: "Edit Icon",
                transientIdentifier: "emoji-picker-panel",
                app: app,
                window: window,
                collapsedSidebar: true,
                dismissTransient: dismissEmojiPicker
            )
            exerciseTransientActionFlow(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                menuItem: "Edit Link…",
                transientIdentifier: "shortcut-link-editor-sheet",
                app: app,
                window: window,
                collapsedSidebar: true,
                dismissTransient: dismissShortcutLinkEditor
            )
            assertNewTabButtonOpensCommandPalette(
                fixture: fixture,
                app: app,
                window: window,
                collapsedSidebar: true
            )
        }
        if let folderID = fixture.folderID {
            exerciseTransientActionFlow(
                elementID: "folder-header-\(folderID)",
                menuItem: "Change Folder Icon…",
                transientIdentifier: "folder-icon-picker-sheet",
                app: app,
                window: window,
                collapsedSidebar: true,
                dismissTransient: dismissFolderIconPicker
            )
            assertNewTabButtonOpensCommandPalette(
                fixture: fixture,
                app: app,
                window: window,
                collapsedSidebar: true
            )
        }
        if fixture.folderID != nil, fixture.folderLauncherID != nil {
            ensureFolderExpanded(fixture, app: app, window: window, collapsedSidebar: true)
            exerciseTransientActionFlow(
                elementID: "folder-shortcut-\(fixture.folderLauncherID!)",
                menuItem: "Edit Link…",
                transientIdentifier: "shortcut-link-editor-sheet",
                app: app,
                window: window,
                collapsedSidebar: true,
                dismissTransient: dismissShortcutLinkEditor
            )
        }
    }

    func testPersonalVisibleSidebarActionAffordancesWorkAfterContextMenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        if let topLevelLauncherID = fixture.topLevelLauncherID {
            exerciseLauncherActionButtonAfterContextMenuDismiss(
                launcherID: topLevelLauncherID,
                app: app,
                window: window,
                collapsedSidebar: false
            )
        }
        exerciseRegularTabCloseButtonAfterContextMenuDismiss(
            tabID: fixture.regularTabID,
            alternateHoverTabID: fixture.secondaryRegularTabID,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    func testPersonalCollapsedHoverSidebarActionAffordancesWorkAfterContextMenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        toggleSidebarVisibility(app: app, window: window)
        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: true)
        if let topLevelLauncherID = fixture.topLevelLauncherID {
            exerciseLauncherActionButtonAfterContextMenuDismiss(
                launcherID: topLevelLauncherID,
                app: app,
                window: window,
                collapsedSidebar: true
            )
        }
        exerciseRegularTabCloseButtonAfterContextMenuDismiss(
            tabID: fixture.regularTabID,
            alternateHoverTabID: fixture.secondaryRegularTabID,
            app: app,
            window: window,
            collapsedSidebar: true
        )
    }

    func testPersonalVisibleSidebarDragReinitiatesAfterContextMenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        guard let topLevelLauncherID = fixture.topLevelLauncherID else {
            XCTFail("Smoke fixture does not expose a top-level launcher")
            return
        }
        exerciseSidebarDragStartAfterContextMenuInteraction(
            elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
            expectedMenuItem: "Edit Link…",
            expectedDragItemID: topLevelLauncherID,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    func testPersonalVisibleLivePinnedLauncherDragReinitiatesAfterContextMenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        guard let topLevelLauncherID = fixture.topLevelLauncherID else {
            XCTFail("Smoke fixture does not expose a top-level launcher")
            return
        }

        let rowID = "space-pinned-shortcut-\(topLevelLauncherID)"
        let row = requireElement(
            withIdentifier: rowID,
            in: app,
            window: window,
            collapsedSidebar: false
        )
        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        let selectionLine = waitForSidebarMarkerLine(
            named: "shortcutRowSelectionChange",
            sourceID: rowID,
            timeout: 3
        )
        XCTAssertTrue(
            selectionLine?.contains("selected=true") == true,
            "Pinned launcher \(rowID) did not emit live selected-row marker before context-menu drag recovery. Selection marker: \(selectionLine ?? "nil"). Marker: \(sidebarDragMarkerContents())"
        )

        exerciseSidebarDragStartAfterContextMenuInteraction(
            elementID: rowID,
            expectedMenuItem: "Edit Link…",
            expectedDragItemID: topLevelLauncherID,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    func testPersonalVisibleRegularTabDragReinitiatesAfterContextMenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        exerciseSidebarDragStartAfterContextMenuInteraction(
            elementID: "tab-row-\(fixture.regularTabID)",
            expectedMenuItem: "Copy Link",
            expectedDragItemID: fixture.regularTabID,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    func testPersonalVisibleSidebarDragReinitiatesAfterContextMenuActionDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        guard let topLevelLauncherID = fixture.topLevelLauncherID else {
            XCTFail("Smoke fixture does not expose a top-level launcher")
            return
        }
        exerciseSidebarDragStartAfterContextMenuInteraction(
            elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
            expectedMenuItem: "Edit Link…",
            expectedDragItemID: topLevelLauncherID,
            app: app,
            window: window,
            collapsedSidebar: false,
            menuActionTitle: "Edit Link…",
            dismissPresentedUI: { app, window in
                self.dismissShortcutLinkEditor(app: app, window: window)
            }
        )
    }

    func testPersonalVisibleRegularTabDragReordersAfterContextMenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        exerciseRegularTabDragAfterContextMenuInteraction(
            fixture: fixture,
            sourceTabID: fixture.regularTabID,
            targetTabID: fixture.secondaryRegularTabID,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    func testPersonalVisibleRegularTabDragRecoversAfterMoveDownContextMenuAction() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        exerciseRegularTabDragAfterSourcePreservingContextMenuAction(
            fixture: fixture,
            sourceTabID: fixture.regularTabID,
            targetTabID: fixture.secondaryRegularTabID,
            menuActionTitle: "Move Down",
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    func testPersonalCollapsedHoverRegularTabDragRecoversAfterMoveDownContextMenuAction() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        toggleSidebarVisibility(app: app, window: window)
        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: true)
        exerciseRegularTabDragAfterSourcePreservingContextMenuAction(
            fixture: fixture,
            sourceTabID: fixture.regularTabID,
            targetTabID: fixture.secondaryRegularTabID,
            menuActionTitle: "Move Down",
            app: app,
            window: window,
            collapsedSidebar: true
        )
    }

    func testPersonalVisiblePinnedLauncherBecomesRegularTabAfterMoveToRegularTabs() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        guard let topLevelLauncherID = fixture.topLevelLauncherID else {
            XCTFail("Smoke fixture does not expose a top-level launcher row")
            return
        }

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        exerciseSidebarDragAfterSourceRemovingContextMenuAction(
            sourceElementID: "space-pinned-shortcut-\(topLevelLauncherID)",
            expectedMenuItem: "Edit Link…",
            menuActionTitle: "Move to Regular Tabs",
            expectedSourceDragItemID: topLevelLauncherID,
            controlElementID: "tab-row-\(fixture.regularTabID)",
            expectedControlDragItemID: fixture.regularTabID,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    func testPersonalVisibleEssentialRemovalKeepsRegularTabDragInteractive() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        guard let essentialID = fixture.essentialID else {
            XCTFail("Smoke fixture does not expose an essential tile")
            return
        }

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        exerciseSidebarDragAfterSourceRemovingContextMenuAction(
            sourceElementID: "essential-shortcut-\(essentialID)",
            expectedMenuItem: "Remove from Essentials",
            menuActionTitle: "Remove from Essentials",
            expectedSourceDragItemID: essentialID,
            controlElementID: "tab-row-\(fixture.regularTabID)",
            expectedControlDragItemID: fixture.regularTabID,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    func testPersonalCollapsedHoverEssentialRemovalKeepsRegularTabDragInteractive() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        guard let essentialID = fixture.essentialID else {
            XCTFail("Smoke fixture does not expose an essential tile")
            return
        }

        toggleSidebarVisibility(app: app, window: window)
        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: true)
        exerciseSidebarDragAfterSourceRemovingContextMenuAction(
            sourceElementID: "essential-shortcut-\(essentialID)",
            expectedMenuItem: "Remove from Essentials",
            menuActionTitle: "Remove from Essentials",
            expectedSourceDragItemID: essentialID,
            controlElementID: "tab-row-\(fixture.regularTabID)",
            expectedControlDragItemID: fixture.regularTabID,
            app: app,
            window: window,
            collapsedSidebar: true
        )
    }

    func testPersonalVisibleEssentialMoveToRegularTabsKeepsRegularTabDragInteractive() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        guard let essentialID = fixture.essentialID else {
            XCTFail("Smoke fixture does not expose an essential tile")
            return
        }

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        exerciseSidebarDragAfterSourceRemovingContextMenuAction(
            sourceElementID: "essential-shortcut-\(essentialID)",
            expectedMenuItem: "Remove from Essentials",
            menuActionTitle: "Move to Regular Tabs",
            expectedSourceDragItemID: essentialID,
            controlElementID: "tab-row-\(fixture.regularTabID)",
            expectedControlDragItemID: fixture.regularTabID,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    func testPersonalVisibleRegularTabDragRecoversAfterDuplicateContextMenuAction() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let initialRegularTabCount = regularTabCount(in: fixture)
        XCTAssertNotNil(
            initialRegularTabCount,
            "Smoke fixture could not resolve initial regular tab count"
        )
        guard let initialRegularTabCount else { return }

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        exerciseSidebarDragAfterSourcePreservingContextMenuAction(
            sourceElementID: "tab-row-\(fixture.regularTabID)",
            expectedMenuItem: "Copy Link",
            menuActionTitle: "Duplicate",
            expectedSourceDragItemID: fixture.regularTabID,
            controlElementID: "tab-row-\(fixture.secondaryRegularTabID)",
            expectedControlDragItemID: fixture.secondaryRegularTabID,
            app: app,
            window: window,
            collapsedSidebar: false,
            postActionSettle: {
                XCTAssertTrue(
                    self.waitForRegularTabCount(
                        initialRegularTabCount + 1,
                        in: fixture,
                        timeout: 5
                    ),
                    "Selecting Duplicate did not increase the regular tab count"
                )
            }
        )
    }

    func testPersonalVisibleRegularTabDragReordersAfterContextMenuSubmenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        exerciseRegularTabDragAfterContextMenuInteraction(
            fixture: fixture,
            sourceTabID: fixture.regularTabID,
            targetTabID: fixture.secondaryRegularTabID,
            app: app,
            window: window,
            collapsedSidebar: false,
            submenuTitle: "Open in Split"
        )
    }

    func testPersonalCollapsedHoverRegularTabDragReordersAfterContextMenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        toggleSidebarVisibility(app: app, window: window)
        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: true)
        exerciseRegularTabDragAfterContextMenuInteraction(
            fixture: fixture,
            sourceTabID: fixture.regularTabID,
            targetTabID: fixture.secondaryRegularTabID,
            app: app,
            window: window,
            collapsedSidebar: true
        )
    }

    func testPersonalCollapsedHoverPinnedDragReinitiatesAfterContextMenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        toggleSidebarVisibility(app: app, window: window)
        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: true)
        guard let topLevelLauncherID = fixture.topLevelLauncherID else {
            XCTFail("Smoke fixture does not expose a top-level launcher")
            return
        }
        exerciseSidebarDragStartAfterContextMenuInteraction(
            elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
            expectedMenuItem: "Edit Link…",
            expectedDragItemID: topLevelLauncherID,
            app: app,
            window: window,
            collapsedSidebar: true
        )
    }

    @MainActor
    private func activatePersonalSpace(
        _ fixture: PersonalSidebarFixture,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool
    ) {
        if collapsedSidebar {
            revealHoverSidebar(in: window)
        }

        let anySpaceIcon = firstSpaceIcon(in: app)
        XCTAssertTrue(
            anySpaceIcon.waitForExistence(timeout: 10),
            "Space switcher did not render any icons. Marker: \(sidebarDragMarkerContents())"
        )

        let personalSpaceIconID = "space-icon-\(fixture.personalSpaceID)"
        let spaceIcon = element(withIdentifier: personalSpaceIconID, in: app)
        if collapsedSidebar, !spaceIcon.waitForExistence(timeout: 1.5) {
            revealHoverSidebar(in: window)
        }
        guard spaceIcon.waitForExistence(timeout: 5) else {
            XCTFail(
                "Personal space icon \(personalSpaceIconID) did not become available. First icon was \(anySpaceIcon.identifier)"
            )
            return
        }
        spaceIcon.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let title = element(withIdentifier: "space-title-\(fixture.personalSpaceID)", in: app)
        XCTAssertTrue(
            title.waitForExistence(timeout: 5),
            "Personal space title did not become available for \(fixture.personalSpaceID). Target icon was \(spaceIcon.identifier)"
        )
        Thread.sleep(forTimeInterval: 0.35)
    }

    @MainActor
    private func ensureFolderExpanded(
        _ fixture: PersonalSidebarFixture,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool
    ) {
        guard let folderLauncherID = fixture.folderLauncherID,
              let folderID = fixture.folderID
        else { return }

        let childIdentifier = "folder-shortcut-\(folderLauncherID)"
        if collapsedSidebar {
            revealHoverSidebar(in: window)
        }

        let child = element(withIdentifier: childIdentifier, in: app)
        if child.waitForExistence(timeout: 1) {
            return
        }

        let header = requireElement(
            withIdentifier: "folder-header-\(folderID)",
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar
        )
        header.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        if collapsedSidebar {
            revealHoverSidebar(in: window)
        }

        XCTAssertTrue(
            child.waitForExistence(timeout: 5),
            "Folder \(folderID) did not expose child shortcut \(folderLauncherID)"
        )
    }

    @MainActor
    private func exerciseContextMenuReopen(
        elementID: String,
        expectedMenuItem: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        openSidebarContextMenu(
            on: target,
            expectedMenuItem: expectedMenuItem,
            app: app,
            file: file,
            line: line
        )
        dismissContextMenu(
            in: window,
            expectedMenuItem: expectedMenuItem,
            app: app,
            file: file,
            line: line
        )

        assertPrimaryClickStillWorks(
            elementID: elementID,
            app: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        let reopenedTarget = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        openSidebarContextMenu(
            on: reopenedTarget,
            expectedMenuItem: expectedMenuItem,
            app: app,
            file: file,
            line: line
        )
        dismissContextMenu(
            in: window,
            expectedMenuItem: expectedMenuItem,
            app: app,
            file: file,
            line: line
        )
    }

    func testPersonalVisibleDriftedLauncherDragRecoversAfterResetToLauncherURLContextMenuAction() throws {
        let fixture = try loadPersonalSidebarFixture()
        guard let topLevelLauncherID = fixture.topLevelLauncherID else {
            XCTFail("Smoke fixture does not expose a top-level launcher row")
            return
        }
        let app = launchApp(additionalEnvironment: sidebarShortcutDriftEnvironment(shortcutPinID: topLevelLauncherID))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        driftLauncherForRuntimeResetActions(
            elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
            app: app,
            window: window,
            collapsedSidebar: false
        )
        exerciseSidebarDragAfterSourcePreservingContextMenuAction(
            sourceElementID: "space-pinned-shortcut-\(topLevelLauncherID)",
            expectedMenuItem: "Edit Link…",
            menuActionTitle: "Reset to Launcher URL",
            expectedSourceDragItemID: topLevelLauncherID,
            controlElementID: "tab-row-\(fixture.regularTabID)",
            expectedControlDragItemID: fixture.regularTabID,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    func testPersonalVisibleDriftedLauncherDragRecoversAfterReplaceLauncherURLContextMenuAction() throws {
        let fixture = try loadPersonalSidebarFixture()
        guard let topLevelLauncherID = fixture.topLevelLauncherID else {
            XCTFail("Smoke fixture does not expose a top-level launcher row")
            return
        }
        let app = launchApp(additionalEnvironment: sidebarShortcutDriftEnvironment(shortcutPinID: topLevelLauncherID))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: false)
        driftLauncherForRuntimeResetActions(
            elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
            app: app,
            window: window,
            collapsedSidebar: false
        )
        exerciseSidebarDragAfterSourcePreservingContextMenuAction(
            sourceElementID: "space-pinned-shortcut-\(topLevelLauncherID)",
            expectedMenuItem: "Edit Link…",
            menuActionTitle: "Replace Launcher URL with Current",
            expectedSourceDragItemID: topLevelLauncherID,
            controlElementID: "tab-row-\(fixture.regularTabID)",
            expectedControlDragItemID: fixture.regularTabID,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    @MainActor
    private func exerciseNewTabButtonAfterContextMenuDismiss(
        contextElementID: String,
        expectedMenuItem: String,
        fixture: PersonalSidebarFixture,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let contextTarget = requireElement(
            withIdentifier: contextElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        openSidebarContextMenu(
            on: contextTarget,
            expectedMenuItem: expectedMenuItem,
            app: app,
            file: file,
            line: line
        )
        dismissContextMenu(
            in: window,
            expectedMenuItem: expectedMenuItem,
            app: app,
            file: file,
            line: line
        )
        assertNewTabButtonOpensCommandPalette(
            fixture: fixture,
            app: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
    }

    @MainActor
    private func assertNewTabButtonOpensCommandPalette(
        fixture: PersonalSidebarFixture,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let newTabButton = requireElement(
            withIdentifier: "space-new-tab-\(fixture.personalSpaceID)",
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        newTabButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(
            waitForCommandPalette(in: app, timeout: 2),
            "New Tab button did not open the floating URL bar",
            file: file,
            line: line
        )
        app.typeKey(.escape, modifierFlags: [])
        _ = waitForNonExistence(element(withIdentifier: "floating-urlbar", in: app), timeout: 2)
    }

    @MainActor
    private func exerciseLauncherActionButtonAfterContextMenuDismiss(
        launcherID: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rowID = "space-pinned-shortcut-\(launcherID)"
        let actionID = "space-pinned-shortcut-action-\(launcherID)"
        let row = requireElement(
            withIdentifier: rowID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        row.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(
            waitForAccessibilityValue(
                "selected",
                elementID: rowID,
                in: app,
                window: window,
                collapsedSidebar: collapsedSidebar,
                timeout: 3
            ),
            "Launcher \(rowID) did not become selected before action-button smoke",
            file: file,
            line: line
        )

        let selectedRow = requireElement(
            withIdentifier: rowID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        openSidebarContextMenu(
            on: selectedRow,
            expectedMenuItem: "Edit Link…",
            app: app,
            file: file,
            line: line
        )
        dismissContextMenu(
            in: window,
            expectedMenuItem: "Edit Link…",
            app: app,
            file: file,
            line: line
        )

        let actionButton = requireElement(
            withIdentifier: actionID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        actionButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(
            waitForElementMissingOrAccessibilityValue(
                "not selected",
                elementID: rowID,
                in: app,
                window: window,
                collapsedSidebar: collapsedSidebar,
                timeout: 3
            ),
            "Launcher action button \(actionID) did not unload or remove \(rowID)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func exerciseRegularTabCloseButtonAfterContextMenuDismiss(
        tabID: String,
        alternateHoverTabID: String? = nil,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rowID = "space-regular-tab-\(tabID)"
        let closeID = "space-regular-tab-close-\(tabID)"
        let row = requireElement(
            withIdentifier: rowID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        openSidebarContextMenu(
            on: row,
            expectedMenuItem: "Copy Link",
            app: app,
            file: file,
            line: line
        )
        dismissContextMenu(
            in: window,
            expectedMenuItem: "Copy Link",
            app: app,
            file: file,
            line: line
        )

        let closeRow = requireElement(
            withIdentifier: rowID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        if accessibilityValue(of: closeRow) != "selected",
           let alternateHoverTabID
        {
            let alternateRowID = "space-regular-tab-\(alternateHoverTabID)"
            let alternateRow = requireElement(
                withIdentifier: alternateRowID,
                in: app,
                window: window,
                collapsedSidebar: collapsedSidebar,
                file: file,
                line: line
            )
            alternateRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
            XCTAssertTrue(
                waitForElementMissing(closeID, in: app, timeout: 1),
                "Regular tab close button \(closeID) stayed exposed after hovering \(alternateRowID)",
                file: file,
                line: line
            )
        }
        closeRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
        let closeButton = requireElement(
            withIdentifier: closeID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        closeButton.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(
            waitForElementMissing(rowID, in: app, timeout: 3),
            "Regular tab close button \(closeID) did not remove \(rowID)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func waitForCommandPalette(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element(withIdentifier: "floating-urlbar", in: app).exists
                || element(withIdentifier: "floating-urlbar-input", in: app).exists
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return element(withIdentifier: "floating-urlbar", in: app).exists
            || element(withIdentifier: "floating-urlbar-input", in: app).exists
    }

    @MainActor
    private func performLauncherDragNoOp(
        elementID: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        let start = target.coordinate(withNormalizedOffset: CGVector(dx: 0.25, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.82, dy: 0.5))
        start.press(forDuration: 0.6, thenDragTo: end)

        let afterDrag = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        openSidebarContextMenu(
            on: afterDrag,
            expectedMenuItem: "Edit Link…",
            app: app,
            file: file,
            line: line
        )
        dismissContextMenu(
            in: window,
            expectedMenuItem: "Edit Link…",
            app: app,
            file: file,
            line: line
        )
    }

    @MainActor
    private func exerciseRegularTabDragAfterContextMenuInteraction(
        fixture: PersonalSidebarFixture,
        sourceTabID: String,
        targetTabID: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        submenuTitle: String? = nil,
        expectedSubmenuItem: String? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sourceElementID = "tab-row-\(sourceTabID)"
        let targetElementID = "tab-row-\(targetTabID)"

        XCTAssertTrue(
            waitForRegularTabRelativeOrder(
                sourceTabID,
                targetTabID,
                in: fixture,
                sourceShouldBeAfterTarget: false,
                timeout: 1
            ),
            "Smoke fixture did not start with \(sourceElementID) before \(targetElementID)",
            file: file,
            line: line
        )

        let source = requireElement(
            withIdentifier: sourceElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        openSidebarContextMenu(
            on: source,
            expectedMenuItem: "Copy Link",
            app: app,
            file: file,
            line: line
        )

        if let submenuTitle {
            openContextSubmenu(
                submenuTitle,
                expectedSubmenuItem: expectedSubmenuItem,
                app: app,
                file: file,
                line: line
            )
        }

        dismissContextMenu(
            in: window,
            expectedMenuItem: "Copy Link",
            app: app,
            file: file,
            line: line
        )

        let sourceAfterMenu = requireElement(
            withIdentifier: sourceElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        let target = requireElement(
            withIdentifier: targetElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        try? FileManager.default.removeItem(at: sidebarDragMarkerFileURL())
        let start = sourceAfterMenu.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9))
        start.press(forDuration: 0.6, thenDragTo: end)
        assertSidebarDragEventChain(
            sourceID: sourceElementID,
            expectedDragItemID: sourceTabID,
            markerDescription: "regular tab reorder after context menu",
            file: file,
            line: line
        )

        XCTAssertTrue(
            waitForRegularTabRelativeOrder(
                sourceTabID,
                targetTabID,
                in: fixture,
                sourceShouldBeAfterTarget: true,
                timeout: 5
            ),
            "Sidebar drag after context menu did not reorder \(sourceElementID) below \(targetElementID)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func exerciseRegularTabDragAfterSourcePreservingContextMenuAction(
        fixture: PersonalSidebarFixture,
        sourceTabID: String,
        targetTabID: String,
        menuActionTitle: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sourceElementID = "tab-row-\(sourceTabID)"
        let targetElementID = "tab-row-\(targetTabID)"
        let markerURL = sidebarDragMarkerFileURL()

        XCTAssertTrue(
            waitForRegularTabRelativeOrder(
                sourceTabID,
                targetTabID,
                in: fixture,
                sourceShouldBeAfterTarget: false,
                timeout: 1
            ),
            "Smoke fixture did not start with \(sourceElementID) before \(targetElementID)",
            file: file,
            line: line
        )

        let sourceBeforeAction = requireElement(
            withIdentifier: sourceElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        let preActionBridgeLine = latestSidebarMarkerLine(
            namedAny: ["bridgeUpdate", "bridgeMake"],
            sourceID: sourceElementID,
            markerURL: markerURL
        )
        let preActionViewID = preActionBridgeLine.flatMap { markerField(named: "view", in: $0) }
        let preActionBridgeTimestamp = preActionBridgeLine.flatMap(markerTimestamp)

        try? FileManager.default.removeItem(at: markerURL)
        performSidebarMarkerStartOnlyDrag(on: sourceBeforeAction)
        assertSidebarDragEventChain(
            sourceID: sourceElementID,
            expectedDragItemID: sourceTabID,
            expectedRouteOwnerView: preActionViewID,
            markerDescription: "baseline regular tab drag before \(menuActionTitle)",
            file: file,
            line: line
        )

        openSidebarContextMenu(
            on: sourceBeforeAction,
            expectedMenuItem: "Copy Link",
            app: app,
            file: file,
            line: line
        )
        chooseContextMenuItem(
            menuActionTitle,
            app: app,
            file: file,
            line: line
        )

        XCTAssertTrue(
            waitForRegularTabRelativeOrder(
                sourceTabID,
                targetTabID,
                in: fixture,
                sourceShouldBeAfterTarget: true,
                timeout: 5
            ),
            "Selecting \(menuActionTitle) did not move \(sourceElementID) below \(targetElementID)",
            file: file,
            line: line
        )

        let sourceAfterAction = requireElement(
            withIdentifier: sourceElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        let targetAfterAction = requireElement(
            withIdentifier: targetElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        let postActionBridgeLine = waitForSidebarMarkerLine(
            namedAny: ["bridgeUpdate", "bridgeMake"],
            sourceID: sourceElementID,
            newerThan: preActionBridgeTimestamp,
            timeout: 3
        ) ?? latestSidebarMarkerLine(
            namedAny: ["bridgeUpdate", "bridgeMake"],
            sourceID: sourceElementID,
            markerURL: markerURL
        )
        let postActionViewID = postActionBridgeLine.flatMap { markerField(named: "view", in: $0) } ?? preActionViewID
        XCTAssertNotNil(
            postActionViewID,
            "Missing live AppKit view marker for \(sourceElementID) after \(menuActionTitle). Marker: \(sidebarDragMarkerContents())",
            file: file,
            line: line
        )

        try? FileManager.default.removeItem(at: markerURL)
        performSidebarMarkerStartOnlyDrag(on: targetAfterAction)
        assertSidebarDragEventChain(
            sourceID: targetElementID,
            expectedDragItemID: targetTabID,
            markerDescription: "different regular tab drag after \(menuActionTitle)",
            file: file,
            line: line
        )

        try? FileManager.default.removeItem(at: markerURL)
        let start = sourceAfterAction.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = targetAfterAction.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
        start.press(forDuration: 0.6, thenDragTo: end)
        assertSidebarDragEventChain(
            sourceID: sourceElementID,
            expectedDragItemID: sourceTabID,
            expectedRouteOwnerView: postActionViewID,
            markerDescription: "regular tab drag after \(menuActionTitle)",
            file: file,
            line: line
        )

        XCTAssertTrue(
            waitForRegularTabRelativeOrder(
                sourceTabID,
                targetTabID,
                in: fixture,
                sourceShouldBeAfterTarget: false,
                timeout: 5
            ),
            "Sidebar drag after \(menuActionTitle) did not reorder \(sourceElementID) back above \(targetElementID)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func exerciseSidebarDragAfterSourcePreservingContextMenuAction(
        sourceElementID: String,
        expectedMenuItem: String,
        menuActionTitle: String,
        expectedSourceDragItemID: String,
        controlElementID: String,
        expectedControlDragItemID: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        postActionSettle: (@MainActor () -> Void)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let markerURL = sidebarDragMarkerFileURL()
        let sourceBeforeAction = requireElement(
            withIdentifier: sourceElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        let preActionBridgeLine = latestSidebarMarkerLine(
            namedAny: ["bridgeUpdate", "bridgeMake"],
            sourceID: sourceElementID,
            markerURL: markerURL
        )
        let preActionViewID = preActionBridgeLine.flatMap { markerField(named: "view", in: $0) }
        let preActionBridgeTimestamp = preActionBridgeLine.flatMap(markerTimestamp)

        try? FileManager.default.removeItem(at: markerURL)
        performSidebarMarkerStartOnlyDrag(on: sourceBeforeAction)
        assertSidebarDragEventChain(
            sourceID: sourceElementID,
            expectedDragItemID: expectedSourceDragItemID,
            expectedRouteOwnerView: preActionViewID,
            markerDescription: "baseline drag before \(menuActionTitle)",
            file: file,
            line: line
        )

        let sourceBeforeMenu = requireElement(
            withIdentifier: sourceElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        openSidebarContextMenu(
            on: sourceBeforeMenu,
            expectedMenuItem: expectedMenuItem,
            app: app,
            file: file,
            line: line
        )
        chooseContextMenuItem(
            menuActionTitle,
            app: app,
            file: file,
            line: line
        )
        postActionSettle?()

        let postActionBridgeLine = waitForSidebarMarkerLine(
            namedAny: ["bridgeUpdate", "bridgeMake"],
            sourceID: sourceElementID,
            newerThan: preActionBridgeTimestamp,
            timeout: 3
        ) ?? latestSidebarMarkerLine(
            namedAny: ["bridgeUpdate", "bridgeMake"],
            sourceID: sourceElementID,
            markerURL: markerURL
        )
        let postActionViewID = postActionBridgeLine.flatMap { markerField(named: "view", in: $0) } ?? preActionViewID
        let postActionMarkerContents = sidebarDragMarkerContents()
        XCTAssertNotNil(
            postActionViewID,
            "Missing live AppKit view marker for \(sourceElementID) after \(menuActionTitle). Marker: \(sidebarDragMarkerContents())",
            file: file,
            line: line
        )

        try? FileManager.default.removeItem(at: markerURL)
        let controlAfterAction = requireElement(
            withIdentifier: controlElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        performSidebarMarkerStartOnlyDrag(on: controlAfterAction)
        assertSidebarDragEventChain(
            sourceID: controlElementID,
            expectedDragItemID: expectedControlDragItemID,
            markerDescription: "different source drag after \(menuActionTitle)",
            file: file,
            line: line
        )

        let sourceAfterAction = element(withIdentifier: sourceElementID, in: app)
        if !sourceAfterAction.waitForExistence(timeout: 1) {
            scrollSidebarTowardTarget(
                sourceElementID,
                in: app,
                window: window,
                collapsedSidebar: collapsedSidebar
            )
        }
        guard sourceAfterAction.waitForExistence(timeout: 1) else {
            XCTFail(
                "Source \(sourceElementID) disappeared after \(menuActionTitle). Post-action marker: \(postActionMarkerContents) Sidebar snapshot: \(sidebarIdentifierSnapshot(in: app))",
                file: file,
                line: line
            )
            return
        }
        XCTAssertTrue(
            sourceAfterAction.exists,
            "Source \(sourceElementID) disappeared after \(menuActionTitle). Post-action marker: \(postActionMarkerContents) Sidebar snapshot: \(sidebarIdentifierSnapshot(in: app))",
            file: file,
            line: line
        )
        try? FileManager.default.removeItem(at: markerURL)
        performSidebarMarkerStartOnlyDrag(on: sourceAfterAction)
        assertSidebarDragEventChain(
            sourceID: sourceElementID,
            expectedDragItemID: expectedSourceDragItemID,
            expectedRouteOwnerView: postActionViewID,
            markerDescription: "source drag after \(menuActionTitle)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func exerciseSidebarDragAfterSourceRemovingContextMenuAction(
        sourceElementID: String,
        expectedMenuItem: String,
        menuActionTitle: String,
        expectedSourceDragItemID: String,
        controlElementID: String,
        expectedControlDragItemID: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let markerURL = sidebarDragMarkerFileURL()
        let sourceBeforeAction = requireElement(
            withIdentifier: sourceElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        let preActionBridgeLine = latestSidebarMarkerLine(
            namedAny: ["bridgeUpdate", "bridgeMake"],
            sourceID: sourceElementID,
            markerURL: markerURL
        )
        let preActionViewID = preActionBridgeLine.flatMap { markerField(named: "view", in: $0) }

        try? FileManager.default.removeItem(at: markerURL)
        performSidebarMarkerStartOnlyDrag(on: sourceBeforeAction)
        assertSidebarDragEventChain(
            sourceID: sourceElementID,
            expectedDragItemID: expectedSourceDragItemID,
            expectedRouteOwnerView: preActionViewID,
            markerDescription: "baseline drag before \(menuActionTitle)",
            file: file,
            line: line
        )

        openSidebarContextMenu(
            on: sourceBeforeAction,
            expectedMenuItem: expectedMenuItem,
            app: app,
            file: file,
            line: line
        )
        chooseContextMenuItem(
            menuActionTitle,
            app: app,
            file: file,
            line: line
        )

        XCTAssertTrue(
            waitForElementMissing(sourceElementID, in: app, timeout: 5),
            "Source \(sourceElementID) remained visible after \(menuActionTitle)",
            file: file,
            line: line
        )

        try? FileManager.default.removeItem(at: markerURL)
        let controlAfterAction = requireElement(
            withIdentifier: controlElementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        performSidebarMarkerStartOnlyDrag(on: controlAfterAction)
        assertSidebarDragEventChain(
            sourceID: controlElementID,
            expectedDragItemID: expectedControlDragItemID,
            markerDescription: "different source drag after \(menuActionTitle)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func exerciseSidebarDragStartAfterContextMenuInteraction(
        elementID: String,
        expectedMenuItem: String,
        expectedDragItemID: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        menuActionTitle: String? = nil,
        dismissPresentedUI: (@MainActor (XCUIApplication, XCUIElement) -> Void)? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        try? FileManager.default.removeItem(at: sidebarDragMarkerFileURL())
        performSidebarMarkerStartOnlyDrag(on: target)
        let baselineDragItemID = waitForSidebarDragStart(timeout: 3)
        XCTAssertNotNil(
            baselineDragItemID,
            "Sidebar drag did not start for \(elementID) before context menu interaction; UI smoke gesture is invalid. Marker: \(sidebarDragMarkerContents())",
            file: file,
            line: line
        )
        guard baselineDragItemID != nil else { return }

        openSidebarContextMenu(
            on: target,
            expectedMenuItem: expectedMenuItem,
            app: app,
            file: file,
            line: line
        )

        if let menuActionTitle {
            chooseContextMenuItem(
                menuActionTitle,
                app: app,
                file: file,
                line: line
            )
            if let dismissPresentedUI {
                let transient = element(withIdentifier: "shortcut-link-editor-sheet", in: app)
                XCTAssertTrue(
                    transient.waitForExistence(timeout: 5),
                    "Expected transient UI after selecting \(menuActionTitle)",
                    file: file,
                    line: line
                )
                dismissPresentedUI(app, window)
                XCTAssertTrue(
                    waitForNonExistence(transient, timeout: 5),
                    "Transient UI did not close after selecting \(menuActionTitle)",
                    file: file,
                    line: line
                )
            }
        } else {
            dismissContextMenu(
                in: window,
                expectedMenuItem: expectedMenuItem,
                app: app,
                file: file,
                line: line
            )
        }

        try? FileManager.default.removeItem(at: sidebarDragMarkerFileURL())
        let sourceAfterMenu = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        performSidebarMarkerStartOnlyDrag(on: sourceAfterMenu)
        assertSidebarDragEventChain(
            sourceID: elementID,
            expectedDragItemID: expectedDragItemID,
            markerDescription: "drag restart after context menu",
            file: file,
            line: line
        )
    }

    @MainActor
    private func performSidebarMarkerDrag(on element: XCUIElement, in window: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.8))
        start.press(forDuration: 0.6, thenDragTo: end)
    }

    @MainActor
    private func performSidebarMarkerStartOnlyDrag(on element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 28, dy: 0))
        start.press(forDuration: 0.6, thenDragTo: end)
    }

    @MainActor
    private func exerciseTransientActionFlow(
        elementID: String,
        menuItem: String,
        transientIdentifier: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        opensWithPrimaryClick: Bool = false,
        dismissTransient: @MainActor (XCUIApplication, XCUIElement) -> Void,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let target = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        if opensWithPrimaryClick {
            openPrimaryClickMenu(
                on: target,
                expectedMenuItem: menuItem,
                app: app,
                file: file,
                line: line
            )
        } else {
            openSidebarContextMenu(
                on: target,
                expectedMenuItem: menuItem,
                app: app,
                file: file,
                line: line
            )
        }
        chooseContextMenuItem(
            menuItem,
            app: app,
            file: file,
            line: line
        )

        let transient = element(withIdentifier: transientIdentifier, in: app)
        XCTAssertTrue(
            transient.waitForExistence(timeout: 5),
            "Expected transient UI \(transientIdentifier) after selecting \(menuItem)",
            file: file,
            line: line
        )

        dismissTransient(app, window)
        XCTAssertTrue(
            waitForNonExistence(transient, timeout: 5),
            "Transient UI \(transientIdentifier) did not close",
            file: file,
            line: line
        )

        assertPrimaryClickStillWorks(
            elementID: elementID,
            app: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        let reopenedTarget = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        if opensWithPrimaryClick {
            openPrimaryClickMenu(
                on: reopenedTarget,
                expectedMenuItem: menuItem,
                app: app,
                file: file,
                line: line
            )
        } else {
            openSidebarContextMenu(
                on: reopenedTarget,
                expectedMenuItem: menuItem,
                app: app,
                file: file,
                line: line
            )
        }
        dismissContextMenu(
            in: window,
            expectedMenuItem: menuItem,
            app: app,
            file: file,
            line: line
        )
    }

    @MainActor
    private func requireElement(
        withIdentifier identifier: String,
        in app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> XCUIElement {
        if collapsedSidebar {
            revealHoverSidebar(in: window)
        }

        let target = element(withIdentifier: identifier, in: app)
        if target.waitForExistence(timeout: 5) {
            return target
        }

        scrollSidebarTowardTarget(identifier, in: app, window: window, collapsedSidebar: collapsedSidebar)
        if target.waitForExistence(timeout: 1) {
            return target
        }

        XCTFail(
            "Missing sidebar target \(identifier). Marker: \(sidebarDragMarkerContents()) Sidebar snapshot: \(sidebarIdentifierSnapshot(in: app))",
            file: file,
            line: line
        )
        return target
    }

    @MainActor
    private func assertPrimaryClickStillWorks(
        elementID: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let expectedValue: String?
        let target = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        if elementID.hasPrefix("folder-header-") {
            let currentValue = accessibilityValue(of: target)
            expectedValue = currentValue == "expanded" ? "collapsed" : "expanded"
        } else if elementID.hasPrefix("essential-shortcut-")
                    || elementID.hasPrefix("space-pinned-shortcut-")
                    || elementID.hasPrefix("folder-shortcut-")
                    || elementID.hasPrefix("space-regular-tab-")
        {
            expectedValue = "selected"
        } else {
            return
        }

        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        if collapsedSidebar {
            revealHoverSidebar(in: window)
        }

        guard let expectedValue else { return }
        XCTAssertTrue(
            waitForAccessibilityValue(
                expectedValue,
                elementID: elementID,
                in: app,
                window: window,
                collapsedSidebar: collapsedSidebar,
                timeout: 2
            ),
            "Primary click on \(elementID) did not produce accessibility value \(expectedValue)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func waitForAccessibilityValue(
        _ expectedValue: String,
        elementID: String,
        in app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if collapsedSidebar {
                revealHoverSidebar(in: window)
            }
            let candidate = element(withIdentifier: elementID, in: app)
            if candidate.exists,
               accessibilityValue(of: candidate) == expectedValue
            {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let candidate = element(withIdentifier: elementID, in: app)
        return candidate.exists && accessibilityValue(of: candidate) == expectedValue
    }

    @MainActor
    private func waitForElementMissingOrAccessibilityValue(
        _ expectedValue: String,
        elementID: String,
        in app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if collapsedSidebar {
                revealHoverSidebar(in: window)
            }
            let candidate = element(withIdentifier: elementID, in: app)
            if !candidate.exists || accessibilityValue(of: candidate) == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let candidate = element(withIdentifier: elementID, in: app)
        return !candidate.exists || accessibilityValue(of: candidate) == expectedValue
    }

    @MainActor
    private func waitForElementMissing(
        _ elementID: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element(withIdentifier: elementID, in: app).exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return !element(withIdentifier: elementID, in: app).exists
    }

    private func accessibilityValue(of element: XCUIElement) -> String? {
        element.value as? String
    }

    @MainActor
    private func scrollSidebarTowardTarget(
        _ identifier: String,
        in app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool
    ) {
        let scrollViewPredicate = NSPredicate(format: "identifier BEGINSWITH %@", "space-view-scroll-")
        let scrollView = app.scrollViews.matching(scrollViewPredicate).firstMatch
        guard scrollView.waitForExistence(timeout: 1) else { return }

        func scroll(
            _ action: () -> Void,
            attempts: Int
        ) -> Bool {
            for _ in 0..<attempts {
                if collapsedSidebar {
                    revealHoverSidebar(in: window)
                }
                action()
                if element(withIdentifier: identifier, in: app).waitForExistence(timeout: 0.5) {
                    return true
                }
            }
            return false
        }

        if scroll({ scrollView.swipeDown() }, attempts: 5) {
            return
        }

        _ = scroll({ scrollView.swipeUp() }, attempts: 5)
    }

    @MainActor
    private func firstSpaceIcon(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "space-icon-")
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor
    private func element(withIdentifier identifier: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor
    private func openSidebarContextMenu(
        on element: XCUIElement,
        expectedMenuItem: String,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
        XCTAssertTrue(
            waitForMenuItem(expectedMenuItem, in: app, hittable: true, timeout: 2),
            file: file,
            line: line
        )
    }

    @MainActor
    private func openPrimaryClickMenu(
        on element: XCUIElement,
        expectedMenuItem: String,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()
        XCTAssertTrue(
            waitForMenuItem(expectedMenuItem, in: app, hittable: true, timeout: 2),
            file: file,
            line: line
        )
    }

    @MainActor
    private func chooseContextMenuItem(
        _ title: String,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let item = app.menuItems[title]
        XCTAssertTrue(
            waitForMenuItem(title, in: app, hittable: true, timeout: 2),
            "Missing context menu item \(title)",
            file: file,
            line: line
        )
        item.click()
    }

    @MainActor
    private func openContextSubmenu(
        _ title: String,
        expectedSubmenuItem: String? = nil,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let item = app.menuItems[title]
        XCTAssertTrue(
            waitForMenuItem(title, in: app, hittable: true, timeout: 2),
            "Missing context submenu \(title)",
            file: file,
            line: line
        )
        item.coordinate(withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)).hover()
        guard let expectedSubmenuItem else { return }
        if !waitForMenuItem(expectedSubmenuItem, in: app, hittable: true, timeout: 0.6) {
            item.click()
        }
        if !waitForMenuItem(expectedSubmenuItem, in: app, hittable: true, timeout: 0.6) {
            app.typeKey(XCUIKeyboardKey.rightArrow.rawValue, modifierFlags: [])
        }
        XCTAssertTrue(
            waitForMenuItem(expectedSubmenuItem, in: app, hittable: true, timeout: 2.5),
            "Missing submenu item \(expectedSubmenuItem) under \(title)",
            file: file,
            line: line
        )
    }

    @MainActor
    private func dismissContextMenu(
        in window: XCUIElement,
        expectedMenuItem: String,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.85, dy: 0.2)).click()
        if !waitForMenuItem(expectedMenuItem, in: app, hittable: false, timeout: 0.3) {
            app.typeKey(.escape, modifierFlags: [])
        }
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    @MainActor
    private func waitForMenuItem(
        _ title: String,
        in app: XCUIApplication,
        hittable: Bool,
        timeout: TimeInterval
    ) -> Bool {
        let item = app.menuItems[title]
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if hittable {
                if item.exists && item.isHittable {
                    return true
                }
            } else if !item.exists || !item.isHittable {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return hittable ? (item.exists && item.isHittable) : (!item.exists || !item.isHittable)
    }

    @MainActor
    private func dismissThemePicker(app: XCUIApplication, window: XCUIElement) {
        Thread.sleep(forTimeInterval: 0.25)
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.08)).click()
    }

    @MainActor
    private func dismissEmojiPicker(app: XCUIApplication, window: XCUIElement) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.08)).click()
    }

    @MainActor
    private func dismissSpaceSettingsDialog(app: XCUIApplication, window: XCUIElement) {
        app.buttons["Cancel"].click()
    }

    @MainActor
    private func dismissShortcutLinkEditor(app: XCUIApplication, window: XCUIElement) {
        app.buttons["Cancel"].click()
    }

    @MainActor
    private func driftLauncherForRuntimeResetActions(
        elementID: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let launcherRow = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )

        launcherRow.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).click()

        let driftedRow = requireElement(
            withIdentifier: elementID,
            in: app,
            window: window,
            collapsedSidebar: collapsedSidebar,
            file: file,
            line: line
        )
        openSidebarContextMenu(
            on: driftedRow,
            expectedMenuItem: "Edit Link…",
            app: app,
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.menuItems["Reset to Launcher URL"].waitForExistence(timeout: 2),
            "Reset action did not appear after drifting launcher \(elementID)",
            file: file,
            line: line
        )
        XCTAssertTrue(
            app.menuItems["Replace Launcher URL with Current"].waitForExistence(timeout: 2),
            "Replace action did not appear after drifting launcher \(elementID)",
            file: file,
            line: line
        )
        dismissContextMenu(
            in: window,
            expectedMenuItem: "Edit Link…",
            app: app,
            file: file,
            line: line
        )
    }

    private func sidebarShortcutDriftEnvironment(shortcutPinID: String) -> [String: String] {
        [
            smokeShortcutDriftPinEnvironmentKey: shortcutPinID,
            smokeShortcutDriftURLEnvironmentKey: "https://example.com/sumi-smoke-drift-\(UUID().uuidString)"
        ]
    }

    @MainActor
    private func dismissFolderIconPicker(app: XCUIApplication, window: XCUIElement) {
        app.buttons["Done"].click()
    }

    @MainActor
    private func revealHoverSidebar(in window: XCUIElement) {
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.2))
        edge.withOffset(CGVector(dx: 2, dy: 0)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    @MainActor
    private func toggleSidebarVisibility(app: XCUIApplication, window: XCUIElement) {
        app.activate()
        window.click()
        app.typeKey("s", modifierFlags: .command)
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))
    }

    @MainActor
    private func assertNativeTrafficLightsHittable(
        in app: XCUIApplication,
        window: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let closeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.closeButton,
            in: app
        )
        let minimizeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.minimizeButton,
            in: app
        )
        let zoomButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.zoomButton,
            in: app
        )

        for (identifier, element) in [
            (BrowserWindowControlIdentifiers.closeButton, closeButton),
            (BrowserWindowControlIdentifiers.minimizeButton, minimizeButton),
            (BrowserWindowControlIdentifiers.zoomButton, zoomButton),
        ] {
            XCTAssertTrue(
                waitForElementToBecomeHittable(element, timeout: 3),
                "Browser traffic light \(identifier) was not hittable. Window frame: \(window.frame)",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    private func resizeWindow(_ window: XCUIElement, horizontalOffset: CGFloat) {
        let start = window.coordinate(withNormalizedOffset: CGVector(dx: 0.995, dy: 0.995))
        let end = start.withOffset(CGVector(dx: horizontalOffset, dy: 0))
        start.press(forDuration: 0.1, thenDragTo: end)
        RunLoop.current.run(until: Date().addingTimeInterval(0.35))
    }

    @MainActor
    private func waitForElementToBecomeHittable(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists && element.isHittable {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return element.exists && element.isHittable
    }

    @MainActor
    private func waitForNonExistence(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return !element.exists
    }

    @MainActor
    private func waitForSidebarDragMarker(
        containing expectedDragItemID: String,
        timeout: TimeInterval
    ) -> Bool {
        let markerURL = sidebarDragMarkerFileURL()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let contents = try? String(contentsOf: markerURL, encoding: .utf8),
               contents.contains("event=startDrag item=\(expectedDragItemID)") {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        if let contents = try? String(contentsOf: markerURL, encoding: .utf8) {
            return contents.contains("event=startDrag item=\(expectedDragItemID)")
        }
        return false
    }

    private func waitForSidebarMarkerEvent(
        named eventName: String,
        sourceID: String,
        timeout: TimeInterval
    ) -> Bool {
        let markerURL = sidebarDragMarkerFileURL()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if markerFileContainsEvent(named: eventName, sourceID: sourceID, markerURL: markerURL) {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return markerFileContainsEvent(named: eventName, sourceID: sourceID, markerURL: markerURL)
    }

    private func waitForSidebarMarkerLine(
        named eventName: String,
        sourceID: String,
        timeout: TimeInterval
    ) -> String? {
        let markerURL = sidebarDragMarkerFileURL()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = latestSidebarMarkerLine(
                namedAny: [eventName],
                sourceID: sourceID,
                markerURL: markerURL
            ) {
                return line
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return latestSidebarMarkerLine(
            namedAny: [eventName],
            sourceID: sourceID,
            markerURL: markerURL
        )
    }

    private func waitForSidebarMarkerLine(
        namedAny eventNames: [String],
        sourceID: String,
        newerThan timestamp: TimeInterval?,
        timeout: TimeInterval
    ) -> String? {
        let markerURL = sidebarDragMarkerFileURL()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let line = latestSidebarMarkerLine(
                namedAny: eventNames,
                sourceID: sourceID,
                markerURL: markerURL,
                newerThan: timestamp
            ) {
                return line
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return latestSidebarMarkerLine(
            namedAny: eventNames,
            sourceID: sourceID,
            markerURL: markerURL,
            newerThan: timestamp
        )
    }

    private func sidebarDragMarkerContents() -> String {
        (try? String(contentsOf: sidebarDragMarkerFileURL(), encoding: .utf8)) ?? "<missing>"
    }

    @MainActor
    private func sidebarIdentifierSnapshot(in app: XCUIApplication) -> String {
        let prefixes = [
            "space-pinned-shortcut-",
            "space-pinned-shortcut-action-",
            "space-pinned-shortcut-reset-",
            "folder-shortcut-",
            "essential-shortcut-",
            "tab-row-",
        ]
        let summary = prefixes.flatMap { prefix -> [String] in
            let predicate = NSPredicate(format: "identifier BEGINSWITH %@", prefix)
            let matches = app.descendants(matching: .any).matching(predicate).allElementsBoundByIndex.prefix(10)
            return matches.map { element in
                let value = (element.value as? String) ?? "nil"
                return "\(element.identifier){exists=\(element.exists),hittable=\(element.isHittable),value=\(value)}"
            }
        }
        return summary.prefix(40).joined(separator: ", ")
    }

    private func waitForSidebarDragStart(timeout: TimeInterval) -> String? {
        let markerURL = sidebarDragMarkerFileURL()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let itemID = latestSidebarDragStartItemID(from: markerURL) {
                return itemID
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        return latestSidebarDragStartItemID(from: markerURL)
    }

    private func latestSidebarDragStartItemID(from markerURL: URL) -> String? {
        guard let contents = try? String(contentsOf: markerURL, encoding: .utf8) else {
            return nil
        }
        return contents
            .split(separator: "\n")
            .reversed()
            .first { $0.contains("event=startDrag") }?
            .split(separator: " ")
            .first { $0.hasPrefix("item=") }
            .map { String($0.dropFirst("item=".count)) }
    }

    private func markerFileContainsEvent(
        named eventName: String,
        sourceID: String,
        markerURL: URL
    ) -> Bool {
        guard let contents = try? String(contentsOf: markerURL, encoding: .utf8) else {
            return false
        }
        return contents
            .split(separator: "\n")
            .contains { line in
                line.contains("event=\(eventName)") && markerLine(line, matchesSourceID: sourceID)
            }
    }

    private func latestSidebarMarkerLine(
        namedAny eventNames: [String],
        sourceID: String,
        markerURL: URL,
        newerThan timestamp: TimeInterval? = nil
    ) -> String? {
        guard let contents = try? String(contentsOf: markerURL, encoding: .utf8) else {
            return nil
        }
        return contents
            .split(separator: "\n")
            .reversed()
            .first { line in
                eventNames.contains(where: { line.contains("event=\($0)") })
                    && markerLine(line, matchesSourceID: sourceID)
                    && markerTimestamp(from: String(line)).map { timestamp == nil || $0 > timestamp! } != false
            }
            .map(String.init)
    }

    private func markerLine(_ line: Substring, matchesSourceID sourceID: String) -> Bool {
        line.contains("sourceID=\(sourceID)") || line.contains("source=\(sourceID)")
    }

    private func markerField(named field: String, in line: String) -> String? {
        line
            .split(separator: " ")
            .first { $0.hasPrefix("\(field)=") }
            .map { String($0.dropFirst(field.count + 1)) }
    }

    private func markerTimestamp(from line: String) -> TimeInterval? {
        markerField(named: "timestamp", in: line).flatMap(TimeInterval.init)
    }

    private func assertSidebarDragEventChain(
        sourceID: String,
        expectedDragItemID: String,
        expectedRouteOwnerView: String? = nil,
        markerDescription: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let routeLine = waitForSidebarMarkerLine(named: "route", sourceID: sourceID, timeout: 3)
        XCTAssertNotNil(
            routeLine,
            "Sidebar drag \(markerDescription) did not route the left mouse-down to source \(sourceID). Marker: \(sidebarDragMarkerContents())",
            file: file,
            line: line
        )
        if let routeLine {
            XCTAssertTrue(
                routeLine.contains("ownerSource=\(sourceID)"),
                "Sidebar drag \(markerDescription) routed a different owner than visible source \(sourceID). Route: \(routeLine)",
                file: file,
                line: line
            )
            XCTAssertTrue(
                routeLine.contains("ownerInHostedRoot=true"),
                "Sidebar drag \(markerDescription) routed an owner outside the current hosted sidebar root for \(sourceID). Route: \(routeLine)",
                file: file,
                line: line
            )
            if let expectedRouteOwnerView {
                XCTAssertTrue(
                    routeLine.contains("ownerView=\(expectedRouteOwnerView)"),
                    "Sidebar drag \(markerDescription) routed a stale view for \(sourceID). Expected \(expectedRouteOwnerView). Route: \(routeLine)",
                    file: file,
                    line: line
                )
            }
        }
        let mouseDownLine = waitForSidebarMarkerLine(named: "mouseDown", sourceID: sourceID, timeout: 3)
        XCTAssertNotNil(
            mouseDownLine,
            "Sidebar drag \(markerDescription) did not deliver mouseDown to live source \(sourceID). Marker: \(sidebarDragMarkerContents())",
            file: file,
            line: line
        )
        if let mouseDownLine {
            XCTAssertTrue(
                mouseDownLine.contains("capturesDrag=true"),
                "Sidebar drag \(markerDescription) delivered mouseDown to \(sourceID) but drag capture was disabled. MouseDown: \(mouseDownLine). Marker: \(sidebarDragMarkerContents())",
                file: file,
                line: line
            )
        }
        XCTAssertTrue(
            waitForSidebarMarkerEvent(named: "mouseDragged", sourceID: sourceID, timeout: 3),
            "Sidebar drag \(markerDescription) did not deliver mouseDragged to live source \(sourceID). Marker: \(sidebarDragMarkerContents())",
            file: file,
            line: line
        )
        XCTAssertTrue(
            waitForSidebarDragMarker(containing: expectedDragItemID, timeout: 3),
            "Sidebar drag \(markerDescription) did not reach startDrag for live source \(sourceID). Marker: \(sidebarDragMarkerContents())",
            file: file,
            line: line
        )
    }

    private func latestSidebarBridgeViewID(sourceID: String) -> String? {
        latestSidebarMarkerLine(
            namedAny: ["bridgeUpdate", "bridgeMake"],
            sourceID: sourceID,
            markerURL: sidebarDragMarkerFileURL()
        ).flatMap { markerField(named: "view", in: $0) }
    }

    private func loadPersonalSidebarFixture() throws -> PersonalSidebarFixture {
        let storeURL = try prepareSmokeStoreURL()

        let personalSpaceID = try requiredScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZSPACEENTITY
            WHERE ZNAME = 'Personal'
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Current profile does not contain a Personal space"
        )

        let profileID = try requiredScalar(
            sql: """
            SELECT lower(hex(ZPROFILEID)) AS value
            FROM ZSPACEENTITY
            WHERE lower(hex(ZID)) = '\(personalSpaceID)'
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have a profile id"
        )

        let topLevelLauncherID = try optionalScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZTABENTITY
            WHERE ZISSPACEPINNED = 1
              AND lower(hex(ZSPACEID)) = '\(personalSpaceID)'
              AND ZFOLDERID IS NULL
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have a top-level launcher"
        ) ?? insertSmokeTab(
            storeURL: storeURL,
            name: "Smoke Launcher",
            urlString: "https://example.com/sumi-smoke-launcher",
            isPinned: false,
            isSpacePinned: true,
            spaceID: personalSpaceID,
            profileID: nil,
            folderID: nil,
            indexWhereClause: """
            ZISSPACEPINNED = 1
              AND lower(hex(ZSPACEID)) = '\(personalSpaceID)'
              AND ZFOLDERID IS NULL
            """
        )

        let regularTabWhereClause = """
        lower(hex(ZSPACEID)) = '\(personalSpaceID)'
          AND COALESCE(ZISSPACEPINNED, 0) = 0
          AND COALESCE(ZISPINNED, 0) = 0
          AND ZFOLDERID IS NULL
        """
        let regularTabID = try insertSmokeTab(
            storeURL: storeURL,
            name: "Smoke Regular Tab",
            urlString: "https://example.com/sumi-smoke-regular",
            isPinned: false,
            isSpacePinned: false,
            spaceID: personalSpaceID,
            profileID: profileID,
            folderID: nil,
            indexWhereClause: regularTabWhereClause
        )
        let secondaryRegularTabID = try insertSmokeTab(
            storeURL: storeURL,
            name: "Smoke Secondary Regular Tab",
            urlString: "https://example.com/sumi-smoke-regular-secondary",
            isPinned: false,
            isSpacePinned: false,
            spaceID: personalSpaceID,
            profileID: profileID,
            folderID: nil,
            indexWhereClause: regularTabWhereClause
        )
        try moveSmokeRegularTabsToTop(
            storeURL: storeURL,
            personalSpaceID: personalSpaceID,
            primaryTabID: regularTabID,
            secondaryTabID: secondaryRegularTabID
        )

        let folderID = try optionalScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZFOLDERENTITY
            WHERE lower(hex(ZSPACEID)) = '\(personalSpaceID)'
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Personal space \(personalSpaceID) does not have a folder"
        ) ?? insertSmokeFolder(
            storeURL: storeURL,
            name: "Smoke Folder",
            spaceID: personalSpaceID
        )

        let folderLauncherID = try optionalScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZTABENTITY
            WHERE ZISSPACEPINNED = 1
              AND lower(hex(ZFOLDERID)) = '\(folderID)'
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Folder \(folderID) does not have a launcher child"
        ) ?? insertSmokeTab(
            storeURL: storeURL,
            name: "Smoke Folder Launcher",
            urlString: "https://example.com/sumi-smoke-folder-launcher",
            isPinned: false,
            isSpacePinned: true,
            spaceID: personalSpaceID,
            profileID: nil,
            folderID: folderID,
            indexWhereClause: """
            ZISSPACEPINNED = 1
              AND lower(hex(ZFOLDERID)) = '\(folderID)'
            """
        )

        let essentialID = try optionalScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZTABENTITY
            WHERE ZISPINNED = 1
              AND lower(hex(ZPROFILEID)) = '\(profileID)'
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Profile \(profileID) does not have an essential shortcut"
        ) ?? insertSmokeTab(
            storeURL: storeURL,
            name: "Smoke Essential",
            urlString: "https://example.com/sumi-smoke-essential",
            isPinned: true,
            isSpacePinned: false,
            spaceID: nil,
            profileID: profileID,
            folderID: nil,
            indexWhereClause: """
            ZISPINNED = 1
              AND lower(hex(ZPROFILEID)) = '\(profileID)'
            """
        )

        return PersonalSidebarFixture(
            personalSpaceID: try accessibilityUUIDString(fromHex: personalSpaceID),
            profileID: profileID,
            topLevelLauncherID: try accessibilityUUIDString(fromHex: topLevelLauncherID),
            regularTabID: try accessibilityUUIDString(fromHex: regularTabID),
            secondaryRegularTabID: try accessibilityUUIDString(fromHex: secondaryRegularTabID),
            folderID: try accessibilityUUIDString(fromHex: folderID),
            folderLauncherID: try accessibilityUUIDString(fromHex: folderLauncherID),
            essentialID: try accessibilityUUIDString(fromHex: essentialID)
        )
    }

    private func prepareSmokeStoreURL() throws -> URL {
        let sourceStoreURL = defaultStoreURL()
        guard FileManager.default.fileExists(atPath: sourceStoreURL.path) else {
            throw FixtureError.missingStore(sourceStoreURL.path)
        }

        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiSmoke-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        let storeURL = directory.appendingPathComponent("default.store", isDirectory: false)
        try backupSQLiteStore(sourceStoreURL, to: storeURL)

        smokeAppSupportURL = directory
        smokeAppSupportDirectories.append(directory)
        return storeURL
    }

    private func prepareStartupThemeSmokeFixture() throws -> URL {
        let storeURL = try prepareSmokeStoreURL()
        let spaceID = try firstSpaceID(in: storeURL)

        let gradientData = try startupSmokeGradientData()
        try executeSQLite(
            sql: """
            UPDATE ZSPACEENTITY
            SET ZWORKSPACETHEMEDATA = NULL,
                ZGRADIENTDATA = \(sqlBlob(hexString(from: gradientData)))
            WHERE lower(hex(ZID)) = '\(spaceID)';
            """,
            storeURL: storeURL
        )

        let snapshotData = try startupSmokeWindowSessionData(spaceID: spaceID)
        return try preparePreferencesHome(windowSessionSnapshotData: snapshotData)
    }

    private func prepareSmokePreferencesHome() throws -> URL {
        let storeURL = smokeStoreURL ?? defaultStoreURL()
        let spaceID = try preferredSmokeStartupSpaceID(in: storeURL)
        let snapshotData = try startupSmokeWindowSessionData(spaceID: spaceID)
        return try preparePreferencesHome(windowSessionSnapshotData: snapshotData)
    }

    private func preferredSmokeStartupSpaceID(in storeURL: URL) throws -> String {
        try optionalScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZSPACEENTITY
            WHERE ZNAME = 'Personal'
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Current profile does not contain a Personal space"
        ) ?? firstSpaceID(in: storeURL)
    }

    private func firstSpaceID(in storeURL: URL) throws -> String {
        try requiredScalar(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZSPACEENTITY
            ORDER BY ZINDEX
            LIMIT 1;
            """,
            storeURL: storeURL,
            description: "Current profile does not contain a space"
        )
    }

    private func startupSmokeGradientData() throws -> Data {
        try JSONSerialization.data(
            withJSONObject: [
                "angle": 132.0,
                "grain": 0.0,
                "opacity": 1.0,
                "nodes": [
                    [
                        "id": UUID().uuidString,
                        "colorHex": "#FF3B30",
                        "location": 0.0
                    ],
                    [
                        "id": UUID().uuidString,
                        "colorHex": "#34C759",
                        "location": 1.0
                    ]
                ]
            ],
            options: []
        )
    }

    private func startupSmokeWindowSessionData(spaceID: String) throws -> Data {
        let snapshot: [String: Any] = [
            "currentSpaceId": try accessibilityUUIDString(fromHex: spaceID),
            "isShowingEmptyState": false,
            "activeTabsBySpace": [],
            "activeShortcutsBySpace": [],
            "sidebarWidth": 250.0,
            "savedSidebarWidth": 250.0,
            "sidebarContentWidth": 234.0,
            "isSidebarVisible": true,
            "urlBarDraft": [
                "text": "",
                "navigateCurrentTab": false
            ]
        ]
        return try JSONSerialization.data(withJSONObject: snapshot, options: [])
    }

    private func preparePreferencesHome(windowSessionSnapshotData: Data) throws -> URL {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiSmokePrefs-\(UUID().uuidString)", isDirectory: true)
        let preferencesDirectory = directory
            .appendingPathComponent("Library", isDirectory: true)
            .appendingPathComponent("Preferences", isDirectory: true)
        try FileManager.default.createDirectory(at: preferencesDirectory, withIntermediateDirectories: true)

        let preferencesURL = preferencesDirectory
            .appendingPathComponent("com.sumi.browser.plist", isDirectory: false)
        let plist: [String: Any] = [
            "sumi.windowSession.last.v2": windowSessionSnapshotData
        ]
        let plistData = try PropertyListSerialization.data(
            fromPropertyList: plist,
            format: .binary,
            options: 0
        )
        try plistData.write(to: preferencesURL, options: .atomic)
        let windowSessionOverrideURL = directory
            .appendingPathComponent(smokeWindowSessionOverrideFileName, isDirectory: false)
        try windowSessionSnapshotData.write(to: windowSessionOverrideURL, options: .atomic)

        smokeAppSupportDirectories.append(directory)
        return directory
    }

    private func dominantBlackPixelRatio(in screenshot: XCUIScreenshot) throws -> Double {
        guard let bitmap = NSBitmapImageRep(data: screenshot.pngRepresentation) else {
            throw FixtureError.screenshotFailure("Unable to decode launch screenshot")
        }

        let width = bitmap.pixelsWide
        let height = bitmap.pixelsHigh
        guard width > 0, height > 0 else {
            throw FixtureError.screenshotFailure("Launch screenshot is empty")
        }

        let step = max(1, min(width, height) / 120)
        var blackPixels = 0
        var sampledPixels = 0

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                guard let color = bitmap.colorAt(x: x, y: y)?.usingColorSpace(.sRGB),
                      color.alphaComponent > 0.05
                else { continue }

                let luminance = 0.2126 * color.redComponent
                    + 0.7152 * color.greenComponent
                    + 0.0722 * color.blueComponent
                if luminance < 0.08 {
                    blackPixels += 1
                }
                sampledPixels += 1
            }
        }

        guard sampledPixels > 0 else {
            throw FixtureError.screenshotFailure("Launch screenshot has no sampleable pixels")
        }
        return Double(blackPixels) / Double(sampledPixels)
    }

    private func insertSmokeFolder(
        storeURL: URL,
        name: String,
        spaceID: String
    ) throws -> String {
        let entity = try nextPrimaryKeyInfo(entityName: "FolderEntity", storeURL: storeURL)
        let folderID = uuidHexString()
        let index = try nextIndex(
            storeURL: storeURL,
            tableName: "ZFOLDERENTITY",
            whereClause: "lower(hex(ZSPACEID)) = '\(spaceID)'"
        )

        try executeSQLite(
            sql: """
            INSERT INTO ZFOLDERENTITY (
                Z_PK, Z_ENT, Z_OPT, ZINDEX, ZISOPEN, ZCOLOR, ZICON, ZNAME, ZID, ZSPACEID
            ) VALUES (
                \(entity.primaryKey), \(entity.entity), 1, \(index), 1,
                \(sqlString("#007AFF")), \(sqlString("")), \(sqlString(name)),
                \(sqlBlob(folderID)), \(sqlBlob(spaceID))
            );
            UPDATE Z_PRIMARYKEY
            SET Z_MAX = MAX(Z_MAX, \(entity.primaryKey))
            WHERE Z_NAME = 'FolderEntity';
            """,
            storeURL: storeURL
        )

        return folderID
    }

    private func insertSmokeTab(
        storeURL: URL,
        name: String,
        urlString: String,
        isPinned: Bool,
        isSpacePinned: Bool,
        spaceID: String?,
        profileID: String?,
        folderID: String?,
        indexWhereClause: String
    ) throws -> String {
        let entity = try nextPrimaryKeyInfo(entityName: "TabEntity", storeURL: storeURL)
        let tabID = uuidHexString()
        let index = try nextIndex(
            storeURL: storeURL,
            tableName: "ZTABENTITY",
            whereClause: indexWhereClause
        )

        try executeSQLite(
            sql: """
            INSERT INTO ZTABENTITY (
                Z_PK, Z_ENT, Z_OPT, ZCANGOBACK, ZCANGOFORWARD, ZINDEX,
                ZISPINNED, ZISSPACEPINNED, ZCURRENTURLSTRING, ZICONASSET,
                ZNAME, ZURLSTRING, ZFOLDERID, ZID, ZPROFILEID, ZSPACEID
            ) VALUES (
                \(entity.primaryKey), \(entity.entity), 1, 0, 0, \(index),
                \(isPinned ? 1 : 0), \(isSpacePinned ? 1 : 0),
                \(sqlString(urlString)), \(sqlString("globe")),
                \(sqlString(name)), \(sqlString(urlString)),
                \(sqlBlob(folderID)), \(sqlBlob(tabID)), \(sqlBlob(profileID)), \(sqlBlob(spaceID))
            );
            UPDATE Z_PRIMARYKEY
            SET Z_MAX = MAX(Z_MAX, \(entity.primaryKey))
            WHERE Z_NAME = 'TabEntity';
            """,
            storeURL: storeURL
        )

        return tabID
    }

    private func moveSmokeRegularTabsToTop(
        storeURL: URL,
        personalSpaceID: String,
        primaryTabID: String,
        secondaryTabID: String
    ) throws {
        let existingMinimum = try requiredScalar(
            sql: """
            SELECT COALESCE(MIN(ZINDEX), 0) AS value
            FROM ZTABENTITY
            WHERE lower(hex(ZSPACEID)) = '\(personalSpaceID)'
              AND COALESCE(ZISSPACEPINNED, 0) = 0
              AND COALESCE(ZISPINNED, 0) = 0
              AND ZFOLDERID IS NULL
              AND lower(hex(ZID)) NOT IN (\(sqlString(primaryTabID)), \(sqlString(secondaryTabID)));
            """,
            storeURL: storeURL,
            description: "Unable to determine regular tab order for Personal space \(personalSpaceID)"
        )
        let firstIndex = (Int(existingMinimum) ?? 0) - 2
        let secondIndex = firstIndex + 1

        try executeSQLite(
            sql: """
            UPDATE ZTABENTITY
            SET ZINDEX = CASE lower(hex(ZID))
                WHEN \(sqlString(primaryTabID)) THEN \(firstIndex)
                WHEN \(sqlString(secondaryTabID)) THEN \(secondIndex)
                ELSE ZINDEX
            END
            WHERE lower(hex(ZID)) IN (\(sqlString(primaryTabID)), \(sqlString(secondaryTabID)));
            """,
            storeURL: storeURL
        )
    }

    private func nextPrimaryKeyInfo(
        entityName: String,
        storeURL: URL
    ) throws -> (entity: String, primaryKey: String) {
        let rows = try sqliteRows(
            sql: """
            SELECT Z_ENT AS entity, COALESCE(Z_MAX, 0) + 1 AS primaryKey
            FROM Z_PRIMARYKEY
            WHERE Z_NAME = \(sqlString(entityName))
            LIMIT 1;
            """,
            storeURL: storeURL
        )
        guard let row = rows.first,
              let entity = row["entity"],
              let primaryKey = row["primaryKey"]
        else {
            throw FixtureError.missingValue("Missing primary key metadata for \(entityName)")
        }
        return (entity, primaryKey)
    }

    private func nextIndex(
        storeURL: URL,
        tableName: String,
        whereClause: String
    ) throws -> String {
        try requiredScalar(
            sql: """
            SELECT COALESCE(MAX(ZINDEX), -1) + 1 AS value
            FROM \(tableName)
            WHERE \(whereClause);
            """,
            storeURL: storeURL,
            description: "Unable to allocate smoke fixture index for \(tableName)"
        )
    }

    private func executeSQLite(
        sql: String,
        storeURL: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [storeURL.path, sql]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown sqlite3 error"
            throw FixtureError.sqliteFailure(message)
        }
    }

    private func backupSQLiteStore(
        _ sourceURL: URL,
        to targetURL: URL
    ) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = [sourceURL.path, ".backup '\(targetURL.path)'"]

        let stderr = Pipe()
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown sqlite3 backup error"
            throw FixtureError.sqliteFailure(message)
        }
    }

    private func sqlString(_ value: String) -> String {
        "'\(value.replacingOccurrences(of: "'", with: "''"))'"
    }

    private func sqlBlob(_ hex: String?) -> String {
        guard let hex, !hex.isEmpty else { return "NULL" }
        return "X'\(hex)'"
    }

    private func hexString(from data: Data) -> String {
        data.map { String(format: "%02x", $0) }.joined()
    }

    private func uuidHexString() -> String {
        UUID().uuidString
            .replacingOccurrences(of: "-", with: "")
            .lowercased()
    }

    private func requiredScalar(
        sql: String,
        storeURL: URL,
        description: String
    ) throws -> String {
        let rows = try sqliteRows(sql: sql, storeURL: storeURL)
        guard let value = rows.first?["value"], !value.isEmpty else {
            throw FixtureError.missingValue(description)
        }
        return value
    }

    private func optionalScalar(
        sql: String,
        storeURL: URL,
        description: String
    ) throws -> String? {
        let rows = try sqliteRows(sql: sql, storeURL: storeURL)
        guard let value = rows.first?["value"], !value.isEmpty else {
            return nil
        }
        return value
    }

    private func sqliteRows(
        sql: String,
        storeURL: URL
    ) throws -> [[String: String]] {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sqlite3")
        process.arguments = ["-json", storeURL.path, sql]

        let stdout = Pipe()
        let stderr = Pipe()
        process.standardOutput = stdout
        process.standardError = stderr

        try process.run()
        process.waitUntilExit()

        let stdoutData = stdout.fileHandleForReading.readDataToEndOfFile()
        let stderrData = stderr.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let message = String(data: stderrData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Unknown sqlite3 error"
            throw FixtureError.sqliteFailure(message)
        }

        guard stdoutData.isEmpty == false else { return [] }
        guard let object = try JSONSerialization.jsonObject(with: stdoutData) as? [[String: Any]] else {
            throw FixtureError.malformedJSON
        }

        return object.map { row in
            row.reduce(into: [:]) { partialResult, entry in
                switch entry.value {
                case let string as String:
                    partialResult[entry.key] = string
                case let number as NSNumber:
                    partialResult[entry.key] = number.stringValue
                default:
                    break
                }
            }
        }
    }

    @MainActor
    private func waitForRegularTabRelativeOrder(
        _ sourceTabID: String,
        _ targetTabID: String,
        in fixture: PersonalSidebarFixture,
        sourceShouldBeAfterTarget: Bool,
        timeout: TimeInterval
    ) -> Bool {
        guard let storeURL = smokeStoreURL,
              let sourceHex = try? hexUUIDString(fromAccessibilityUUID: sourceTabID),
              let targetHex = try? hexUUIDString(fromAccessibilityUUID: targetTabID),
              let personalSpaceHex = try? hexUUIDString(fromAccessibilityUUID: fixture.personalSpaceID)
        else {
            return false
        }

        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let orderedRegularTabIDs = (try? sqliteRows(
                sql: """
                SELECT lower(hex(ZID)) AS value
                FROM ZTABENTITY
                WHERE lower(hex(ZSPACEID)) = '\(personalSpaceHex)'
                  AND COALESCE(ZISSPACEPINNED, 0) = 0
                  AND COALESCE(ZISPINNED, 0) = 0
                  AND ZFOLDERID IS NULL
                ORDER BY ZINDEX;
                """,
                storeURL: storeURL
            ))?.compactMap { $0["value"] } ?? []

            if let sourceIndex = orderedRegularTabIDs.firstIndex(of: sourceHex),
               let targetIndex = orderedRegularTabIDs.firstIndex(of: targetHex),
               (sourceShouldBeAfterTarget ? sourceIndex > targetIndex : sourceIndex < targetIndex)
            {
                return true
            }

            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return false
    }

    @MainActor
    private func waitForRegularTabCount(
        _ expectedCount: Int,
        in fixture: PersonalSidebarFixture,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if regularTabCount(in: fixture) == expectedCount {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return regularTabCount(in: fixture) == expectedCount
    }

    private func regularTabCount(in fixture: PersonalSidebarFixture) -> Int? {
        guard let storeURL = smokeStoreURL,
              let personalSpaceHex = try? hexUUIDString(fromAccessibilityUUID: fixture.personalSpaceID)
        else {
            return nil
        }

        return (try? sqliteRows(
            sql: """
            SELECT lower(hex(ZID)) AS value
            FROM ZTABENTITY
            WHERE lower(hex(ZSPACEID)) = '\(personalSpaceHex)'
              AND COALESCE(ZISSPACEPINNED, 0) = 0
              AND COALESCE(ZISPINNED, 0) = 0
              AND ZFOLDERID IS NULL
            ORDER BY ZINDEX;
            """,
            storeURL: storeURL
        ))?.count
    }

    private var smokeStoreURL: URL? {
        smokeAppSupportURL?.appendingPathComponent("default.store", isDirectory: false)
    }

    private func accessibilityUUIDString(fromHex hex: String) throws -> String {
        guard hex.count == 32 else {
            throw FixtureError.missingValue("Malformed UUID hex value \(hex)")
        }

        let part1 = String(hex.prefix(8))
        let part2 = String(hex.dropFirst(8).prefix(4))
        let part3 = String(hex.dropFirst(12).prefix(4))
        let part4 = String(hex.dropFirst(16).prefix(4))
        let part5 = String(hex.dropFirst(20).prefix(12))
        let dashed = "\(part1)-\(part2)-\(part3)-\(part4)-\(part5)"

        guard let uuid = UUID(uuidString: dashed) else {
            throw FixtureError.missingValue("Malformed UUID value \(hex)")
        }

        return uuid.uuidString
    }

    private func hexUUIDString(fromAccessibilityUUID uuidString: String) throws -> String {
        guard let uuid = UUID(uuidString: uuidString) else {
            throw FixtureError.missingValue("Malformed accessibility UUID \(uuidString)")
        }

        return withUnsafeBytes(of: uuid.uuid) { rawBuffer in
            rawBuffer.map { String(format: "%02x", $0) }.joined()
        }
    }

    private func defaultStoreURL() -> URL {
        let homeDirectory: URL
        if let passwd = getpwuid(getuid()) {
            homeDirectory = URL(fileURLWithPath: String(cString: passwd.pointee.pw_dir))
        } else {
            homeDirectory = FileManager.default.homeDirectoryForCurrentUser
        }

        return homeDirectory
            .appendingPathComponent("Library/Application Support/com.sumi.browser/default.store")
    }
}
