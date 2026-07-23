import AppKit
import Darwin
import Foundation
import XCTest

@MainActor
final class SumiSidebarContextMenuUITests: SumiLaunchSmokeUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipUnlessInteractionE2E()
    }

    func testVisibleSidebarContextMenuCanBeReopenedAfterDismiss() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome())
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let spaceIcon = firstSpaceIcon(in: app)
        XCTAssertTrue(spaceIcon.waitForExistence(timeout: 5))

        openSidebarContextMenu(on: spaceIcon, expectedMenuItem: "Space Settings", app: app)
        dismissContextMenu(in: window, expectedMenuItem: "Space Settings", app: app)
        openSidebarContextMenu(on: spaceIcon, expectedMenuItem: "Space Settings", app: app)
    }

    func testCollapsedHoverSidebarContextMenuCanBeReopenedAfterDismiss() throws {
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        revealHoverSidebar(in: window)

        let firstIcon = firstSpaceIcon(in: app)
        XCTAssertTrue(firstIcon.waitForExistence(timeout: 5))
        let spaceIconID = firstIcon.identifier

        let spaceIcon = requireElement(
            withIdentifier: spaceIconID,
            in: app,
            window: window,
            collapsedSidebar: true
        )
        openSidebarContextMenu(on: spaceIcon, expectedMenuItem: "Space Settings", app: app)
        dismissContextMenu(in: window, expectedMenuItem: "Space Settings", app: app)
        let reopenedSpaceIcon = requireElement(
            withIdentifier: spaceIconID,
            in: app,
            window: window,
            collapsedSidebar: true
        )
        openSidebarContextMenu(on: reopenedSpaceIcon, expectedMenuItem: "Space Settings", app: app)
    }

    func testPersonalVisibleSidebarContextMenusCanBeReopenedAfterDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = try launchApp()
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
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

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
        let app = try launchApp()
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
            dismissTransient: Self.dismissThemePicker
        )
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Change Icon",
            transientIdentifier: "emoji-picker-panel",
            app: app,
            window: window,
            collapsedSidebar: false,
            dismissTransient: Self.dismissEmojiPicker
        )
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Space Settings",
            transientIdentifier: "space-edit-dialog",
            app: app,
            window: window,
            collapsedSidebar: false,
            dismissTransient: Self.dismissSpaceSettingsDialog
        )
        if let topLevelLauncherID = fixture.topLevelLauncherID {
            exerciseTransientActionFlow(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                menuItem: "Edit Icon",
                transientIdentifier: "emoji-picker-panel",
                app: app,
                window: window,
                collapsedSidebar: false,
                dismissTransient: Self.dismissEmojiPicker
            )
            exerciseTransientActionFlow(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                menuItem: "Edit Link…",
                transientIdentifier: "shortcut-link-editor-sheet",
                app: app,
                window: window,
                collapsedSidebar: false,
                dismissTransient: Self.dismissShortcutLinkEditor
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
                dismissTransient: Self.dismissFolderIconPicker
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
                dismissTransient: Self.dismissShortcutLinkEditor
            )
        }
    }

    func testPersonalCollapsedHoverSidebarTransientActionsKeepSidebarInteractive() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

        activatePersonalSpace(fixture, app: app, window: window, collapsedSidebar: true)
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Change Theme",
            transientIdentifier: "workspace-theme-picker-panel",
            app: app,
            window: window,
            collapsedSidebar: true,
            dismissTransient: Self.dismissThemePicker
        )
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Change Icon",
            transientIdentifier: "emoji-picker-panel",
            app: app,
            window: window,
            collapsedSidebar: true,
            dismissTransient: Self.dismissEmojiPicker
        )
        exerciseTransientActionFlow(
            elementID: "space-title-\(fixture.personalSpaceID)",
            menuItem: "Space Settings",
            transientIdentifier: "space-edit-dialog",
            app: app,
            window: window,
            collapsedSidebar: true,
            dismissTransient: Self.dismissSpaceSettingsDialog
        )
        if let topLevelLauncherID = fixture.topLevelLauncherID {
            exerciseTransientActionFlow(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                menuItem: "Edit Icon",
                transientIdentifier: "emoji-picker-panel",
                app: app,
                window: window,
                collapsedSidebar: true,
                dismissTransient: Self.dismissEmojiPicker
            )
            exerciseTransientActionFlow(
                elementID: "space-pinned-shortcut-\(topLevelLauncherID)",
                menuItem: "Edit Link…",
                transientIdentifier: "shortcut-link-editor-sheet",
                app: app,
                window: window,
                collapsedSidebar: true,
                dismissTransient: Self.dismissShortcutLinkEditor
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
                dismissTransient: Self.dismissFolderIconPicker
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
                dismissTransient: Self.dismissShortcutLinkEditor
            )
        }
    }

    func testPersonalVisibleSidebarActionAffordancesWorkAfterContextMenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = try launchApp()
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
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

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
        let app = try launchApp()
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
        let app = try launchApp()
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
        let app = try launchApp()
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
        let app = try launchApp()
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
                Self.dismissShortcutLinkEditor(app: app, window: window)
            }
        )
    }

    func testPersonalVisibleRegularTabDragReordersAfterContextMenuDismiss() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = try launchApp()
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
        let app = try launchApp()
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
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

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
        let app = try launchApp()
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
        let app = try launchApp()
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
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        guard let essentialID = fixture.essentialID else {
            XCTFail("Smoke fixture does not expose an essential tile")
            return
        }

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
        let app = try launchApp()
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
        let app = try launchApp()
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
        let app = try launchApp()
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
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

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
        let app = try launchApp(preferencesHomeURL: try prepareSmokePreferencesHome(isSidebarVisible: false))
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))

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


    func testPersonalVisibleDriftedLauncherDragRecoversAfterResetToLauncherURLContextMenuAction() throws {
        let fixture = try loadPersonalSidebarFixture()
        guard let topLevelLauncherID = fixture.topLevelLauncherID else {
            XCTFail("Smoke fixture does not expose a top-level launcher row")
            return
        }
        let app = try launchApp(additionalEnvironment: sidebarShortcutDriftEnvironment(shortcutPinID: topLevelLauncherID))
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
        let app = try launchApp(additionalEnvironment: sidebarShortcutDriftEnvironment(shortcutPinID: topLevelLauncherID))
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
}
