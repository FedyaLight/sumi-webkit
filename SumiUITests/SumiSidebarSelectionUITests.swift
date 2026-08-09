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

    func testVisibleSidebarTracksFavoriteSelectionWithoutRemount() throws {
        try assertVisibleSidebarLauncherSelection { fixture in
            fixture.favoriteID.map { "favorite-shortcut-\($0)" }
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

    func testAutofocusScrollsDownAfterSpaceSwitch() throws {
        try assertAutofocusAfterSpaceSwitch(direction: .down)
    }

    func testAutofocusScrollsUpAfterSpaceSwitch() throws {
        try assertAutofocusAfterSpaceSwitch(direction: .up)
    }

    func testAutofocusScrollsUpToPinnedAfterSpaceSwitch() throws {
        try assertAutofocusAfterSpaceSwitch(
            direction: .up,
            target: .topLevelPinned
        )
    }

    private func assertAutofocusAfterSpaceSwitch(
        direction: AutofocusDirection,
        target: AutofocusTarget = .regular
    ) throws {
        let fixture = try loadPersonalSidebarFixture()
        let autofocusTabIDs = try insertAutofocusScrollFixture(fixture)
        let app = try launchApp()
        let window = app.windows.element(boundBy: 0)

        XCTAssertTrue(window.waitForExistence(timeout: 5))
        activatePersonalSpace(
            fixture,
            app: app,
            window: window,
            collapsedSidebar: false
        )
        let targetRowID: String
        switch target {
        case .regular:
            let targetTabID = try XCTUnwrap(
                direction == .down
                    ? autofocusTabIDs.last
                    : autofocusTabIDs.first
            )
            targetRowID = "tab-row-\(targetTabID)"
        case .topLevelPinned:
            targetRowID = "space-pinned-shortcut-\(try XCTUnwrap(fixture.topLevelLauncherID))"
        }
        let scrollViewPredicate = NSPredicate(
            format: "identifier BEGINSWITH %@",
            "space-view-scroll-"
        )
        let scrollView = app.scrollViews.matching(scrollViewPredicate).firstMatch
        XCTAssertTrue(scrollView.waitForExistence(timeout: 3))
        if direction == .down {
            scrollView.scroll(byDeltaX: 0, deltaY: -2_000)
        }
        XCTAssertTrue(
            waitForElementToBecomeHittable(
                element(withIdentifier: targetRowID, in: app),
                timeout: 3
            ),
            "The 20-row fixture did not expose the autofocus target"
        )
        assertSelectionTransition(
            to: targetRowID,
            deselecting: "tab-row-\(fixture.regularTabID)",
            app: app,
            window: window
        )

        let manualDeltaY: CGFloat = direction == .down ? 2_000 : -2_000
        scrollView.scroll(byDeltaX: 0, deltaY: manualDeltaY)
        XCTAssertFalse(
            isFullyVisible(
                element(withIdentifier: targetRowID, in: app),
                inside: scrollView
            ),
            "The active autofocus target must begin outside the viewport before scrolling \(direction)"
        )

        switchAwayFromPersonalSpaceAndBackForAutofocus(
            fixture,
            app: app,
            window: window
        )
        XCTAssertTrue(
            waitForSelectionState(
                selected: true,
                elementID: targetRowID,
                in: app,
                timeout: 3
            ),
            "Space switch did not restore \(targetRowID) as selected"
        )
        let revealedTarget = element(withIdentifier: targetRowID, in: app)
        XCTAssertTrue(revealedTarget.waitForExistence(timeout: 3))
        let restoredScrollView = app.scrollViews
            .matching(scrollViewPredicate)
            .firstMatch
        XCTAssertTrue(restoredScrollView.waitForExistence(timeout: 3))
        XCTAssertTrue(
            isFullyVisible(revealedTarget, inside: restoredScrollView),
            "Autofocus left the active row partially clipped after scrolling \(direction)"
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

    private enum AutofocusDirection: Equatable {
        case up
        case down
    }

    private enum AutofocusTarget {
        case regular
        case topLevelPinned
    }

    private func switchAwayFromPersonalSpaceAndBackForAutofocus(
        _ fixture: PersonalSidebarFixture,
        app: XCUIApplication,
        window: XCUIElement
    ) {
        let destinationSpaceID = "00000000-0000-0000-0000-00000000A010"
        let otherSpaceIcon = element(
            withIdentifier: "space-icon-\(destinationSpaceID)",
            in: app
        )
        XCTAssertTrue(
            otherSpaceIcon.waitForExistence(timeout: 3),
            "The autofocus fixture did not expose its destination space"
        )
        guard otherSpaceIcon.exists else { return }

        otherSpaceIcon.coordinate(
            withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)
        ).click()
        let destinationTitle = element(
            withIdentifier: "space-title-\(destinationSpaceID)",
            in: app
        )
        XCTAssertTrue(
            Self.waitForObservableReadiness(
                of: destinationTitle,
                timeout: 5
            ),
            "The destination space never became interactive"
        )
        activatePersonalSpace(
            fixture,
            app: app,
            window: window,
            collapsedSidebar: false
        )
    }

    private func isFullyVisible(
        _ element: XCUIElement,
        inside scrollView: XCUIElement
    ) -> Bool {
        guard element.exists, scrollView.exists else { return false }
        let intersection = scrollView.frame.intersection(element.frame)
        return !intersection.isNull
            && intersection.height >= element.frame.height - 1
    }

    private func insertAutofocusScrollFixture(
        _ fixture: PersonalSidebarFixture
    ) throws -> [String] {
        let storeURL = try requiredSmokeStoreURL()
        let destinationSpaceID = "0000000000000000000000000000a010"
        try executeSQLite(
            sql: """
            INSERT INTO spaces (
                id, profile_id, name, icon, position
            ) VALUES (
                \(sqlBlob(destinationSpaceID)), \(sqlBlob(fixture.profileID)),
                \(sqlString("Autofocus Destination")),
                \(sqlString("circle.fill")), 1
            );
            """,
            storeURL: storeURL
        )

        let personalSpaceID = try hexUUIDString(
            fromAccessibilityUUID: fixture.personalSpaceID
        )
        let regularTabWhereClause = """
        lower(hex(space_id)) = '\(personalSpaceID)'
          AND is_space_pinned = 0
          AND is_pinned = 0
          AND folder_id IS NULL
        """
        return try (0..<20).map { index in
            let suffix = String(format: "%04x", 0xb100 + index)
            let tabID = String(repeating: "0", count: 28) + suffix
            try insertSmokeTab(
                storeURL: storeURL,
                id: tabID,
                name: "Autofocus Row \(index + 1)",
                urlString: "https://example.com/sumi-autofocus-\(index)",
                isPinned: false,
                isSpacePinned: false,
                spaceID: personalSpaceID,
                profileID: fixture.profileID,
                folderID: nil,
                indexWhereClause: regularTabWhereClause
            )
            return try accessibilityUUIDString(fromHex: tabID)
        }
    }
}
