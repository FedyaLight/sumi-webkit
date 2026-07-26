import AppKit
import Darwin
import Foundation
import XCTest

extension SumiLaunchSmokeUITestCase {
    @MainActor
    func activatePersonalSpace(
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
            Self.waitForObservableReadiness(of: title, timeout: 5),
            "Personal space title did not become visible and hittable for \(fixture.personalSpaceID). Target icon was \(spaceIcon.identifier)"
        )
    }

    @MainActor
    func ensureFolderExpanded(
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
    func exerciseContextMenuReopen(
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

    @MainActor
    func exerciseNewTabButtonAfterContextMenuDismiss(
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
    func assertNewTabButtonOpensCommandPalette(
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
            "New Tab button did not open the command palette",
            file: file,
            line: line
        )
        app.typeKey(.escape, modifierFlags: [])
        _ = waitForNonExistence(element(withIdentifier: "command-palette", in: app), timeout: 2)
    }

    @MainActor
    func exerciseLauncherActionButtonAfterContextMenuDismiss(
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
    func exerciseRegularTabCloseButtonAfterContextMenuDismiss(
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
           let alternateHoverTabID {
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
    func waitForCommandPalette(
        in app: XCUIApplication,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element(withIdentifier: "command-palette", in: app).exists
                || element(withIdentifier: "command-palette-input", in: app).exists {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return element(withIdentifier: "command-palette", in: app).exists
            || element(withIdentifier: "command-palette-input", in: app).exists
    }

    @MainActor
    func performLauncherDragNoOp(
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
    func exerciseRegularTabDragAfterContextMenuInteraction(
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
    func exerciseRegularTabDragAfterSourcePreservingContextMenuAction(
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
    func exerciseSidebarDragAfterSourcePreservingContextMenuAction(
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
    func exerciseSidebarDragAfterSourceRemovingContextMenuAction(
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
    func exerciseSidebarDragStartAfterContextMenuInteraction(
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
    func performSidebarMarkerDrag(on element: XCUIElement, in window: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1.8))
        start.press(forDuration: 0.6, thenDragTo: end)
    }

    @MainActor
    func performSidebarMarkerStartOnlyDrag(on element: XCUIElement) {
        let start = element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let end = start.withOffset(CGVector(dx: 28, dy: 0))
        start.press(forDuration: 0.6, thenDragTo: end)
    }

    @MainActor
    func exerciseTransientActionFlow(
        elementID: String,
        menuItem: String,
        transientIdentifier: String,
        app: XCUIApplication,
        window: XCUIElement,
        collapsedSidebar: Bool,
        opensWithPrimaryClick: Bool = false,
        dismissTransient: @MainActor @Sendable (XCUIApplication, XCUIElement) -> Void,
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
    func requireElement(
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
    func assertPrimaryClickStillWorks(
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
                    || elementID.hasPrefix("space-regular-tab-") {
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
    func waitForAccessibilityValue(
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
               accessibilityValue(of: candidate) == expectedValue {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }
        let candidate = element(withIdentifier: elementID, in: app)
        return candidate.exists && accessibilityValue(of: candidate) == expectedValue
    }

    @MainActor
    func waitForElementMissingOrAccessibilityValue(
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
    func waitForElementMissing(
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

    func accessibilityValue(of element: XCUIElement) -> String? {
        element.value as? String
    }

    @MainActor
    func scrollSidebarTowardTarget(
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
    func firstSpaceIcon(in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier BEGINSWITH %@", "space-icon-")
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor
    func element(withIdentifier identifier: String, in app: XCUIApplication) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        return app.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor
    func element(withIdentifier identifier: String, inSearchRoot root: XCUIElement) -> XCUIElement {
        let predicate = NSPredicate(format: "identifier == %@", identifier)
        return root.descendants(matching: .any).matching(predicate).firstMatch
    }

    @MainActor
    func openSidebarContextMenu(
        on element: XCUIElement,
        expectedMenuItem: String,
        app: XCUIApplication,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        for _ in 0..<2 {
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).hover()
            RunLoop.current.run(until: Date().addingTimeInterval(0.12))
            element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).rightClick()
            if waitForMenuItem(expectedMenuItem, in: app, hittable: true, timeout: 2) {
                return
            }
            app.typeKey(.escape, modifierFlags: [])
            RunLoop.current.run(until: Date().addingTimeInterval(0.15))
        }

        XCTAssertTrue(
            false,
            "Missing context menu item \(expectedMenuItem). target exists=\(element.exists) hittable=\(element.isHittable) frame=\(element.frame)",
            file: file,
            line: line
        )
    }

    @MainActor
    func openPrimaryClickMenu(
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
    func chooseContextMenuItem(
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
    func openContextSubmenu(
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
    func dismissContextMenu(
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
    func waitForMenuItem(
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
    static func dismissThemePicker(app: XCUIApplication, window: XCUIElement) {
        let predicate = NSPredicate(
            format: "identifier == %@",
            "workspace-theme-picker-panel"
        )
        let picker = app.descendants(matching: .any).matching(predicate).firstMatch
        XCTAssertTrue(
            waitForObservableReadiness(of: picker, timeout: 5),
            "Workspace theme picker did not become visible and hittable before dismissal"
        )
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.08)).click()
    }

    @MainActor
    static func waitForObservableReadiness(
        of element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == true AND hittable == true"),
            object: element
        )
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    @MainActor
    static func dismissEmojiPicker(app: XCUIApplication, window: XCUIElement) {
        window.coordinate(withNormalizedOffset: CGVector(dx: 0.96, dy: 0.08)).click()
    }

    @MainActor
    static func dismissSpaceSettingsDialog(app: XCUIApplication, window: XCUIElement) {
        app.buttons["Cancel"].click()
    }

    @MainActor
    static func dismissShortcutLinkEditor(app: XCUIApplication, window: XCUIElement) {
        app.buttons["Cancel"].click()
    }

    @MainActor
    func driftLauncherForRuntimeResetActions(
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

    func sidebarShortcutDriftEnvironment(shortcutPinID: String) -> [String: String] {
        [
            smokeShortcutDriftPinEnvironmentKey: shortcutPinID,
            smokeShortcutDriftURLEnvironmentKey: "https://example.com/sumi-smoke-drift-\(UUID().uuidString)",
        ]
    }

    @MainActor
    static func dismissFolderIconPicker(app: XCUIApplication, window: XCUIElement) {
        app.buttons["Done"].click()
    }

    @MainActor
    func revealHoverSidebar(in window: XCUIElement) {
        let edge = window.coordinate(withNormalizedOffset: CGVector(dx: 0, dy: 0.2))
        edge.withOffset(CGVector(dx: 2, dy: 0)).hover()
        RunLoop.current.run(until: Date().addingTimeInterval(0.2))
    }

    @MainActor
    func assertNativeTrafficLightsHittable(
        in app: XCUIApplication,
        window: XCUIElement,
        searchRoot: XCUIElement? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let root: XCUIElement = searchRoot ?? app
        let closeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.closeButton,
            inSearchRoot: root
        )
        let minimizeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.minimizeButton,
            inSearchRoot: root
        )
        let zoomButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.zoomButton,
            inSearchRoot: root
        )

        for (identifier, element) in [
            (BrowserWindowControlIdentifiers.closeButton, closeButton),
            (BrowserWindowControlIdentifiers.minimizeButton, minimizeButton),
            (BrowserWindowControlIdentifiers.zoomButton, zoomButton),
        ] {
            XCTAssertTrue(
                waitForTrafficLightElementToBeVisibleAndEnabled(element, timeout: 3),
                "Browser traffic light \(identifier) was not visible and enabled. exists=\(element.exists) enabled=\(element.isEnabled) hittable=\(element.isHittable) frame=\(element.frame). Window frame: \(window.frame)",
                file: file,
                line: line
            )
            XCTAssertGreaterThanOrEqual(
                min(element.frame.width, element.frame.height),
                expectedTrafficLightVisualDiameter,
                "Traffic light hit target should preserve at least the native visual diameter. id=\(identifier) frame=\(element.frame)",
                file: file,
                line: line
            )
            XCTAssertLessThanOrEqual(
                abs(element.frame.width - element.frame.height),
                2,
                "Traffic light hit target should stay close to the native macOS control frame, without visible compression. id=\(identifier) frame=\(element.frame)",
                file: file,
                line: line
            )
        }

        assertTrafficLightFramesAreAligned(
            closeButton: closeButton,
            minimizeButton: minimizeButton,
            zoomButton: zoomButton,
            window: window,
            file: file,
            line: line
        )
        assertTrafficLightsRemainSeparatedFromSidebarToggle(
            app: app,
            zoomButton: zoomButton,
            file: file,
            line: line
        )
    }

    @MainActor
    func assertNativeTrafficLightsHidden(
        in app: XCUIApplication,
        window: XCUIElement,
        searchRoot: XCUIElement? = nil,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let root: XCUIElement = searchRoot ?? app
        let closeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.closeButton,
            inSearchRoot: root
        )
        let minimizeButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.minimizeButton,
            inSearchRoot: root
        )
        let zoomButton = element(
            withIdentifier: BrowserWindowControlIdentifiers.zoomButton,
            inSearchRoot: root
        )

        for (identifier, element) in [
            (BrowserWindowControlIdentifiers.closeButton, closeButton),
            (BrowserWindowControlIdentifiers.minimizeButton, minimizeButton),
            (BrowserWindowControlIdentifiers.zoomButton, zoomButton),
        ] {
            XCTAssertTrue(
                waitForTrafficLightElementToBeHiddenOrDisabled(element, timeout: 3),
                "Browser traffic light \(identifier) should be hidden while collapsed sidebar overlay is closed. exists=\(element.exists) enabled=\(element.isEnabled) hittable=\(element.isHittable) frame=\(element.frame). Window frame: \(window.frame)",
                file: file,
                line: line
            )
        }
    }

    @MainActor
    func assertTrafficLightFramesAreAligned(
        closeButton: XCUIElement,
        minimizeButton: XCUIElement,
        zoomButton: XCUIElement,
        window: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let closeFrame = closeButton.frame
        let minimizeFrame = minimizeButton.frame
        let zoomFrame = zoomButton.frame
        let windowFrame = window.frame

        XCTAssertEqual(
            closeFrame.midY,
            minimizeFrame.midY,
            accuracy: 1.5,
            "Traffic lights should share one visual baseline. close=\(closeFrame) minimize=\(minimizeFrame) zoom=\(zoomFrame)",
            file: file,
            line: line
        )
        XCTAssertEqual(
            minimizeFrame.midY,
            zoomFrame.midY,
            accuracy: 1.5,
            "Traffic lights should share one visual baseline. close=\(closeFrame) minimize=\(minimizeFrame) zoom=\(zoomFrame)",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            minimizeFrame.minX,
            closeFrame.maxX,
            "Minimize button should sit to the right of close button. close=\(closeFrame) minimize=\(minimizeFrame)",
            file: file,
            line: line
        )
        XCTAssertGreaterThan(
            zoomFrame.minX,
            minimizeFrame.maxX,
            "Zoom button should sit to the right of minimize button. minimize=\(minimizeFrame) zoom=\(zoomFrame)",
            file: file,
            line: line
        )
        for (label, spacing) in [
            ("close→minimize", minimizeFrame.midX - closeFrame.midX),
            ("minimize→zoom", zoomFrame.midX - minimizeFrame.midX),
        ] {
            XCTAssertEqual(
                spacing,
                expectedTrafficLightCenterSpacing,
                accuracy: 1,
                "Traffic lights should keep the system centre-to-centre pitch (\(label)). close=\(closeFrame) minimize=\(minimizeFrame) zoom=\(zoomFrame)",
                file: file,
                line: line
            )
        }
        XCTAssertLessThanOrEqual(
            closeFrame.minX,
            windowFrame.minX + 96,
            "Traffic lights should remain inside the sidebar chrome, not float over page content. close=\(closeFrame) window=\(windowFrame)",
            file: file,
            line: line
        )
        XCTAssertLessThanOrEqual(
            closeFrame.minY,
            windowFrame.minY + 64,
            "Traffic lights should remain in the top chrome band. close=\(closeFrame) window=\(windowFrame)",
            file: file,
            line: line
        )
    }

    @MainActor
    func assertTrafficLightsRemainSeparatedFromSidebarToggle(
        app: XCUIApplication,
        zoomButton: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let sidebarToggle = app.buttons["Toggle Sidebar"].firstMatch
        guard sidebarToggle.exists,
              sidebarToggle.frame.minX > zoomButton.frame.maxX
        else {
            return
        }

        XCTAssertGreaterThanOrEqual(
            sidebarToggle.frame.minX - zoomButton.frame.maxX,
            10,
            "Traffic lights should keep a visible gap before the sidebar toggle. zoom=\(zoomButton.frame) toggle=\(sidebarToggle.frame)",
            file: file,
            line: line
        )
    }

    @MainActor
    func waitForElementToBecomeHittable(
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
    func waitForTrafficLightElementToBeVisibleAndEnabled(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if element.exists,
               element.isEnabled,
               element.frame.width > 0,
               element.frame.height > 0 {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return element.exists
            && element.isEnabled
            && element.frame.width > 0
            && element.frame.height > 0
    }

    @MainActor
    func waitForTrafficLightElementToRemainVisibleAndEnabled(
        _ element: XCUIElement,
        duration: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(duration)
        while Date() < deadline {
            guard element.exists,
                  element.isEnabled,
                  element.frame.width > 0,
                  element.frame.height > 0
            else {
                return false
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return element.exists
            && element.isEnabled
            && element.frame.width > 0
            && element.frame.height > 0
    }

    @MainActor
    func waitForTrafficLightElementToBeHiddenOrDisabled(
        _ element: XCUIElement,
        timeout: TimeInterval
    ) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if !element.exists
                || !element.isEnabled
                || element.frame.width <= 0
                || element.frame.height <= 0 {
                return true
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.05))
        }

        return !element.exists
            || !element.isEnabled
            || element.frame.width <= 0
            || element.frame.height <= 0
    }

    @MainActor
    func waitForNonExistence(
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
    func waitForSidebarDragMarker(
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

    func waitForSidebarMarkerEvent(
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

    func waitForSidebarMarkerLine(
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

    func waitForSidebarMarkerLine(
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

    func sidebarDragMarkerContents() -> String {
        (try? String(contentsOf: sidebarDragMarkerFileURL(), encoding: .utf8)) ?? "<missing>"
    }

    @MainActor
    func sidebarIdentifierSnapshot(in app: XCUIApplication) -> String {
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

    func waitForSidebarDragStart(timeout: TimeInterval) -> String? {
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

    func latestSidebarDragStartItemID(from markerURL: URL) -> String? {
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

    func markerFileContainsEvent(
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

    func latestSidebarMarkerLine(
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

    func markerLine(_ line: Substring, matchesSourceID sourceID: String) -> Bool {
        line.contains("sourceID=\(sourceID)") || line.contains("source=\(sourceID)")
    }

    func markerField(named field: String, in line: String) -> String? {
        line
            .split(separator: " ")
            .first { $0.hasPrefix("\(field)=") }
            .map { String($0.dropFirst(field.count + 1)) }
    }

    func markerTimestamp(from line: String) -> TimeInterval? {
        markerField(named: "timestamp", in: line).flatMap(TimeInterval.init)
    }

    func assertSidebarDragEventChain(
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

    func latestSidebarBridgeViewID(sourceID: String) -> String? {
        latestSidebarMarkerLine(
            namedAny: ["bridgeUpdate", "bridgeMake"],
            sourceID: sourceID,
            markerURL: sidebarDragMarkerFileURL()
        ).flatMap { markerField(named: "view", in: $0) }
    }
}
