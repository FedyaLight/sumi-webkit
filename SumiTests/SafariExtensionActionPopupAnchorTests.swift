import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionActionPopupAnchorTests: XCTestCase {
    func testExtensionActionViewDelegatesRuntimePresentationToContext() throws {
        let actionView = try String(
            contentsOf: projectURL("Sumi/Components/Extensions/ExtensionActionView.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(actionView.contains("ExtensionActionPresentationContext("))
        XCTAssertTrue(actionView.contains("presentActionPopup(for: ext)"))
        XCTAssertFalse(
            actionView.contains("openActionPopupFromURLHub("),
            "SwiftUI action controls should not call the extension runtime popup path directly"
        )
        XCTAssertFalse(
            actionView.contains("currentActionTabForClick"),
            "Clicked-tab resolution should live in the action presentation context"
        )
    }

    func testClickCapturesAnchorBeforeAsyncRuntimeLoad() throws {
        let actionView = try String(
            contentsOf: projectURL("Sumi/Components/Extensions/ExtensionActionView.swift"),
            encoding: .utf8
        )
        let actionContext = try String(
            contentsOf: projectURL(
                "Sumi/Components/Extensions/ExtensionActionPresentationContext.swift"
            ),
            encoding: .utf8
        )
        let uiSource = try String(
            contentsOf: projectURL("Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            actionView.contains("actionPresentationContext.presentActionPopup(for: ext)"),
            "ExtensionActionButton should delegate popup presentation to the action context"
        )
        XCTAssertTrue(
            actionContext.contains("captureActionPopupAnchor("),
            "URL-hub click context must capture the popup anchor before async runtime work"
        )
        XCTAssertTrue(
            actionContext.range(
                of: "captureActionPopupAnchor",
                options: .backwards
            ).map { captureRange in
                actionContext.range(
                    of: "openActionPopupFromURLHub",
                    range: captureRange.upperBound..<actionContext.endIndex
                ) != nil
            } == true,
            "Anchor capture must precede openActionPopupFromURLHub in the click handler"
        )
        XCTAssertTrue(
            uiSource.contains("if latestActionPopupAnchorSessionByExtensionID[extensionId] == nil"),
            "Action popup path should defensively capture when click-time anchor is missing"
        )
    }

    func testPresentationUsesResolvedURLHubAnchorsNotPageWebViewFallback() throws {
        let delegateSource = try String(
            contentsOf: projectURL(
                "Sumi/Managers/ExtensionManager/ExtensionManager+ControllerDelegate.swift"
            ),
            encoding: .utf8
        )
        let anchorSource = try String(
            contentsOf: projectURL(
                "Sumi/Managers/ExtensionManager/ExtensionManager+ActionPopupAnchor.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            delegateSource.contains("presentResolvedExtensionActionPopup("),
            "WebKit popup presentation must use the shared anchor resolver"
        )
        XCTAssertFalse(
            delegateSource.contains("contentView.bounds.maxY - 50"),
            "Extension action popups must not fall back to the page window bottom"
        )
        XCTAssertTrue(
            anchorSource.contains("urlHubFallbackAnchorView"),
            "Stale anchors must fall back to the URL-hub site-controls anchor"
        )
        XCTAssertTrue(
            anchorSource.contains("ExtensionActionPopupAnchorResolution"),
            "Anchor resolution must emit sanitized diagnostics"
        )
    }

    func testAnchorModelTracksExtensionProfileWindowAndSession() throws {
        let supportSource = try String(
            contentsOf: projectURL("Sumi/Managers/ExtensionManager/ExtensionManagerSupport.swift"),
            encoding: .utf8
        )
        let anchorSource = try String(
            contentsOf: projectURL(
                "Sumi/Managers/ExtensionManager/ExtensionManager+ActionPopupAnchor.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(supportSource.contains("final class ExtensionActionPopupAnchor"))
        XCTAssertTrue(supportSource.contains("let extensionID: String"))
        XCTAssertTrue(supportSource.contains("let profileID: UUID"))
        XCTAssertTrue(supportSource.contains("let windowID: UUID"))
        XCTAssertTrue(supportSource.contains("let sessionToken: UUID"))
        XCTAssertTrue(supportSource.contains("weak var buttonView: NSView?"))
        XCTAssertTrue(supportSource.contains("enum ExtensionActionPopupAnchorSource"))
        XCTAssertTrue(anchorSource.contains("liveActionAnchorView"))
        XCTAssertTrue(anchorSource.contains("resolveActionPopupAnchor"))
    }

    func testProfileSwitchClearsMismatchedPendingAnchors() throws {
        let profilesSource = try String(
            contentsOf: projectURL("Sumi/Managers/ExtensionManager/ExtensionManager+Profiles.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            profilesSource.contains("clearActionPopupAnchors(notMatching: profileId)"),
            "Profile switches must not reuse popup anchors from another profile"
        )
    }

    func testURLHubPresenterExposesFallbackAnchorLookup() throws {
        let presenterSource = try String(
            contentsOf: projectURL("Sumi/Components/Sidebar/URLBarHubPopoverPresenter.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            presenterSource.contains("func anchorView(for windowID: UUID)"),
            "URL-hub presenter must expose a deterministic fallback anchor"
        )
    }

    func testPrivateTabGuardRemainsBeforePresentation() throws {
        let uiSource = try String(
            contentsOf: projectURL("Sumi/Managers/ExtensionManager/ExtensionManager+UI.swift"),
            encoding: .utf8
        )

        XCTAssertTrue(
            uiSource.contains("currentTab.isEphemeral == false"),
            "Private tabs must remain blocked before action popup presentation"
        )
    }

    func testMultipleExtensionsKeepPerExtensionAnchorSessions() throws {
        let managerSource = try String(
            contentsOf: projectURL("Sumi/Managers/ExtensionManager/ExtensionManager.swift"),
            encoding: .utf8
        )
        let anchorSource = try String(
            contentsOf: projectURL(
                "Sumi/Managers/ExtensionManager/ExtensionManager+ActionPopupAnchor.swift"
            ),
            encoding: .utf8
        )

        XCTAssertTrue(
            managerSource.contains("latestActionPopupAnchorSessionByExtensionID"),
            "Each extension should keep its own latest popup anchor session"
        )
        XCTAssertTrue(
            anchorSource.contains("for extensionId: String"),
            "Anchor resolution must be keyed by extension identifier"
        )
    }

    private func projectURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
