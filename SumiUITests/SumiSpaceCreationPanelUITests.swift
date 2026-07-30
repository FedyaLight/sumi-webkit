import AppKit
import XCTest

final class SumiSpaceCreationPanelUITests: SumiLaunchSmokeUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipUnlessInteractionE2E()
    }

    func testCreateSpacePanelShowsRedesignedFormAndCreatesSpace() throws {
        let app = try launchApp()
        let window = app.windows.element(boundBy: 0)
        XCTAssertTrue(window.waitForExistence(timeout: 5))

        let actionsButton = window.menuButtons["Actions"]
        XCTAssertTrue(actionsButton.waitForExistence(timeout: 5))
        actionsButton.click()

        let newSpaceItem = app.menuItems["New Space"]
        XCTAssertTrue(newSpaceItem.waitForExistence(timeout: 3))
        XCTAssertFalse(
            app.menuItems["Live Folder"].exists,
            "Zen keeps Live Folder creation out of the bottom Actions menu"
        )
        XCTAssertFalse(app.menuItems["New Live Folder"].exists)
        newSpaceItem.click()

        let panel = window.groups["sidebar-space-creation"]
            .firstMatch
        let nameField = window.textFields["sidebar-space-creation-name"]
        XCTAssertTrue(nameField.waitForExistence(timeout: 5))
        try pasteText("Panel Smoke Space", into: nameField, in: app)
        _ = panel

        XCTAssertTrue(window.staticTexts["Create a Space"].exists)
        XCTAssertTrue(
            window.buttons["sidebar-space-creation-theme"].exists,
            "Theme row should be present in the creation panel"
        )
        window.buttons["sidebar-space-creation-theme"].click()

        let picker = app.descendants(matching: .any)
            .matching(identifier: "workspace-theme-picker-panel")
            .firstMatch
        XCTAssertTrue(
            picker.waitForExistence(timeout: 5),
            "Theme editor should open from the Space creation draft"
        )
        let lightMono1Preset = app.buttons[
            "workspace-theme-preset-Light Mono-1"
        ]
        XCTAssertTrue(
            lightMono1Preset.waitForExistence(timeout: 3),
            "Light Mono-1 should be available for live preview"
        )
        lightMono1Preset.click()
        attachScreenshot(app, name: "space-creation-theme-preview")
        Self.dismissThemePicker(app: app, window: window)

        let profileMenu = window.menuButtons[
            "sidebar-space-creation-profile-menu"
        ].firstMatch
        XCTAssertTrue(profileMenu.exists, "Profile picker should be present")
        profileMenu.click()

        let newProfileItem = app.menuItems["New Profile…"]
        XCTAssertTrue(
            newProfileItem.waitForExistence(timeout: 3),
            "Profile menu should offer New Profile…"
        )
        attachScreenshot(app, name: "space-creation-profile-menu")
        profileMenu.typeKey(.escape, modifierFlags: [])

        attachScreenshot(app, name: "space-creation-panel")

        let createButton = window.buttons["Create Space"]
        XCTAssertTrue(createButton.waitForExistence(timeout: 3))
        XCTAssertTrue(createButton.isEnabled)
        createButton.click()

        XCTAssertTrue(
            window.staticTexts["Panel Smoke Space"].waitForExistence(timeout: 5),
            "Created space should appear in the sidebar"
        )
        attachScreenshot(app, name: "space-created")
    }

    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let exportDirectory = ProcessInfo.processInfo.environment[
            "SUMI_UITEST_SCREENSHOT_DIR"
        ] {
            let url = URL(fileURLWithPath: exportDirectory)
                .appendingPathComponent("\(name).png")
            try? app.screenshot().pngRepresentation.write(to: url)
        }
    }
}
