import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionActionPopupActiveTabTests: XCTestCase {
    func testPresentActionPopupDoesNotGrantActiveTabFromLaterActiveWindow() throws {
        let delegateSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
        )
        let presentActionPopup = try methodBody(
            containing: "presentActionPopup action",
            in: delegateSource
        )

        XCTAssertTrue(
            presentActionPopup.contains("presentResolvedExtensionActionPopup("),
            "The active popup path should still use WebKit's native popup delegate presentation"
        )
        XCTAssertFalse(
            presentActionPopup.contains("grantActiveTabURLAccess("),
            "The popup delegate must not grant activeTab from mutable active-window state; URL-hub clicks grant the clicked tab before dispatch"
        )
    }

    func testURLHubClickGrantsActiveTabForClickedTabBeforePopupDispatch() throws {
        let uiSource = try source(
            named: "Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"
        )
        let openActionPopup = try methodBody(
            containing: "func openActionPopupFromURLHub",
            in: uiSource
        )
        let preparePageAccess = try methodBody(
            containing: "private func prepareActionClickPageAccess",
            in: uiSource
        )

        let prepareRange = try XCTUnwrap(
            openActionPopup.range(of: "prepareActionClickPageAccess(")
        )
        let dispatchRange = try XCTUnwrap(
            openActionPopup.range(of: "extensionContext.performAction(for: adapter)")
        )

        XCTAssertLessThan(
            prepareRange.lowerBound.utf16Offset(in: openActionPopup),
            dispatchRange.lowerBound.utf16Offset(in: openActionPopup),
            "Clicked-tab page access must be prepared before WebKit dispatches the action/popup"
        )
        XCTAssertTrue(
            preparePageAccess.contains("(permissions + optionalPermissions).contains(\"activeTab\")"),
            "The click-time access helper must recognize activeTab declarations"
        )
        XCTAssertTrue(
            preparePageAccess.contains("grantActiveTabURLAccess(")
                && preparePageAccess.contains("tab: tab"),
            "The click-time access helper must grant the concrete clicked tab, not a later active tab"
        )
    }

    func testExtensionActionClickResolvesTabOnlyFromClickedWindowState() throws {
        let actionSource = try source(
            named: "Sumi/Components/Extensions/ExtensionActionView.swift"
        )
        let clickResolver = try methodBody(
            containing: "private var currentExtensionActionTab",
            in: actionSource
        )

        XCTAssertTrue(clickResolver.contains("browserManager.currentTab(for: windowState)"))
        XCTAssertTrue(clickResolver.contains("windowState.currentTabId.flatMap"))
        XCTAssertTrue(clickResolver.contains("browserManager.shellSelectionService.currentTab"))
        XCTAssertTrue(clickResolver.contains("for: windowState"))
        XCTAssertFalse(
            clickResolver.contains("windowRegistry?.activeWindow"),
            "Extension action clicks must not fall back to another active window when resolving activeTab"
        )
        XCTAssertFalse(
            clickResolver.contains("tabManager.currentTab"),
            "Extension action clicks must not grant activeTab from global tab manager state"
        )
    }

    private func methodBody(containing needle: String, in source: String) throws -> String {
        guard let start = source.range(of: needle)?.lowerBound else {
            throw XCTSkip("Could not find method containing \(needle)")
        }
        guard let openingBrace = source[start...].firstIndex(of: "{") else {
            throw XCTSkip("Could not find method body for \(needle)")
        }

        var depth = 0
        var index = openingBrace
        while index < source.endIndex {
            switch source[index] {
            case "{":
                depth += 1
            case "}":
                depth -= 1
                if depth == 0 {
                    return String(source[start...index])
                }
            default:
                break
            }
            index = source.index(after: index)
        }

        throw XCTSkip("Could not parse method body for \(needle)")
    }

    private func source(named relativePath: String) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try String(
            contentsOf: repoRoot.appendingPathComponent(relativePath),
            encoding: .utf8
        )
    }
}
