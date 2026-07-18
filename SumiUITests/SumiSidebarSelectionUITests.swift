import XCTest

@MainActor
final class SumiSidebarSelectionUITests: SumiLaunchSmokeUITestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        try skipUnlessInteractionE2E()
    }

    func testVisibleSidebarTracksTopLevelLauncherSelectionWithoutRemount() throws {
        try assertVisibleSidebarLauncherSelection { fixture in
            fixture.topLevelLauncherID.map { "space-pinned-shortcut-\($0)" }
        }
    }

    func testVisibleSidebarTracksFolderLauncherSelectionWithoutRemount() throws {
        try assertVisibleSidebarLauncherSelection(expandFolder: true) { fixture in
            fixture.folderLauncherID.map { "folder-shortcut-\($0)" }
        }
    }

    func testVisibleSidebarTracksEssentialSelectionWithoutRemount() throws {
        try assertVisibleSidebarLauncherSelection { fixture in
            fixture.essentialID.map { "essential-shortcut-\($0)" }
        }
    }

    func testVisibleSidebarRestoresLauncherSelectionAfterSpaceSwitch() throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = try launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        activatePersonalSpace(
            fixture,
            app: app,
            window: window,
            collapsedSidebar: false
        )
        let launcherRowID = try XCTUnwrap(
            fixture.topLevelLauncherID.map { "space-pinned-shortcut-\($0)" }
        )
        assertSelectionTransition(
            to: launcherRowID,
            deselecting: "tab-row-\(fixture.regularTabID)",
            app: app,
            window: window
        )
        switchAwayFromPersonalSpaceAndBackIfAvailable(
            fixture,
            app: app,
            window: window
        )
        XCTAssertTrue(
            waitForSelectionState(
                selected: true,
                elementID: launcherRowID,
                in: app,
                timeout: 3
            ),
            "Space switch did not restore \(launcherRowID) as selected"
        )
    }

    private func assertVisibleSidebarLauncherSelection(
        expandFolder: Bool = false,
        launcherRowID: (PersonalSidebarFixture) -> String?
    ) throws {
        let fixture = try loadPersonalSidebarFixture()
        let app = try launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        activatePersonalSpace(
            fixture,
            app: app,
            window: window,
            collapsedSidebar: false
        )
        if expandFolder {
            ensureFolderExpanded(
                fixture,
                app: app,
                window: window,
                collapsedSidebar: false
            )
        }

        let launcherRowID = try XCTUnwrap(launcherRowID(fixture))
        let initialRegularRowID = "space-regular-tab-\(fixture.regularTabID)"
        assertSelectionTransition(
            to: launcherRowID,
            deselecting: initialRegularRowID,
            app: app,
            window: window
        )
    }

    private func assertSelectionTransition(
        to selectedElementID: String,
        deselecting previousElementID: String,
        app: XCUIApplication,
        window: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let selectedElement = requireElement(
            withIdentifier: selectedElementID,
            in: app,
            window: window,
            collapsedSidebar: false,
            file: file,
            line: line
        )
        selectedElement.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        window.coordinate(
            withNormalizedOffset: CGVector(dx: 0.8, dy: 0.5)
        ).hover()

        let didSelect = waitForSelectionState(
            selected: true,
            elementID: selectedElementID,
            in: app,
            timeout: 3
        )
        if !didSelect {
            let screenshot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
            screenshot.name = "Sidebar selection failure"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertTrue(
            didSelect,
            "\(selectedElementID) did not become selected without remounting the sidebar. "
                + selectionDiagnostics(
                    selectedElementID: selectedElementID,
                    previousElementID: previousElementID,
                    app: app
                ),
            file: file,
            line: line
        )
        XCTAssertTrue(
            waitForSelectionState(
                selected: false,
                elementID: previousElementID,
                in: app,
                timeout: 3
            ),
            "\(previousElementID) stayed selected after activating \(selectedElementID)",
            file: file,
            line: line
        )
    }

    private func waitForSelectionState(
        selected: Bool,
        elementID: String,
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            let candidate = element(withIdentifier: elementID, in: app)
            if !candidate.exists {
                if !selected { return true }
            } else {
                let value = accessibilityValue(of: candidate)
                let stateMatches = selected
                    ? value == "selected" || candidate.isSelected
                    : value != "selected" && !candidate.isSelected
                if stateMatches {
                    return true
                }
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        let candidate = element(withIdentifier: elementID, in: app)
        guard candidate.exists else { return !selected }
        let value = accessibilityValue(of: candidate)
        return selected
            ? value == "selected" || candidate.isSelected
            : value != "selected" && !candidate.isSelected
    }

    private func selectionDiagnostics(
        selectedElementID: String,
        previousElementID: String,
        app: XCUIApplication
    ) -> String {
        func value(for element: XCUIElement) -> String {
            guard element.exists else { return "missing" }
            return accessibilityValue(of: element) ?? "nil"
        }
        let selectedValue = value(
            for: element(withIdentifier: selectedElementID, in: app)
        )
        let previousValue = value(
            for: element(withIdentifier: previousElementID, in: app)
        )
        let urlValue = value(
            for: app.staticTexts.matching(identifier: "sidebar-urlbar").firstMatch
        )
        return "selected=\(selectedValue), previous=\(previousValue), url=\(urlValue)"
    }

    private func switchAwayFromPersonalSpaceAndBackIfAvailable(
        _ fixture: PersonalSidebarFixture,
        app: XCUIApplication,
        window: XCUIElement
    ) {
        let predicate = NSPredicate(
            format: "identifier BEGINSWITH %@ AND identifier != %@",
            "space-icon-",
            "space-icon-\(fixture.personalSpaceID)"
        )
        let otherSpaceIcon = app.descendants(matching: .any)
            .matching(predicate)
            .firstMatch
        guard otherSpaceIcon.waitForExistence(timeout: 1) else { return }

        otherSpaceIcon.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        activatePersonalSpace(
            fixture,
            app: app,
            window: window,
            collapsedSidebar: false
        )
        ensureFolderExpanded(
            fixture,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }
}
