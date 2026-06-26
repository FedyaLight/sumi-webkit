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
            uiSource.contains("actionPopupAnchorStore.latestSessionToken(for: extensionId) == nil"),
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
        let profileId = try uuid("11111111-2222-3333-4444-555555555555")
        let firstWindowId = try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE1")
        let secondWindowId = try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE2")
        let store = ExtensionActionPopupAnchorStore()
        let firstExtensionAnchor = makeAnchor(
            extensionId: "first-extension",
            profileId: profileId,
            windowId: firstWindowId,
            sessionToken: try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0001")
        )
        let secondExtensionAnchor = makeAnchor(
            extensionId: "second-extension",
            profileId: profileId,
            windowId: secondWindowId,
            sessionToken: try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0002")
        )

        store.store(firstExtensionAnchor)
        store.store(secondExtensionAnchor)

        XCTAssertEqual(
            store.latestSessionToken(for: "first-extension"),
            firstExtensionAnchor.sessionToken
        )
        XCTAssertEqual(
            store.latestSessionToken(for: "second-extension"),
            secondExtensionAnchor.sessionToken
        )
        XCTAssertEqual(store.latestAnchor(for: "first-extension")?.windowID, firstWindowId)
        XCTAssertEqual(store.latestAnchor(for: "second-extension")?.windowID, secondWindowId)
    }

    func testAnchorStorePrunesExpiredSessionsOnResolveAndCapture() throws {
        let now = Date(timeIntervalSince1970: 1_000)
        let profileId = try uuid("11111111-2222-3333-4444-555555555555")
        let staleAnchor = makeAnchor(
            extensionId: "stale-extension",
            profileId: profileId,
            sessionToken: try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0011"),
            capturedAt: now.addingTimeInterval(-31)
        )
        let freshAnchor = makeAnchor(
            extensionId: "fresh-extension",
            profileId: profileId,
            sessionToken: try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0012"),
            capturedAt: now
        )
        let store = ExtensionActionPopupAnchorStore(sessionTTL: 30)

        store.store(staleAnchor, now: now)
        XCTAssertNil(store.latestSessionToken(for: "stale-extension", now: now))
        XCTAssertFalse(store.contains(sessionToken: staleAnchor.sessionToken))

        store.store(staleAnchor, now: now)
        store.store(freshAnchor, now: now)
        XCTAssertFalse(store.contains(sessionToken: staleAnchor.sessionToken))
        XCTAssertEqual(store.latestSessionToken(for: "fresh-extension", now: now), freshAnchor.sessionToken)
    }

    func testAnchorStoreEnforcesPendingLimitOldestFirst() throws {
        let now = Date(timeIntervalSince1970: 2_000)
        let profileId = try uuid("11111111-2222-3333-4444-555555555555")
        let oldestAnchor = makeAnchor(
            extensionId: "oldest",
            profileId: profileId,
            sessionToken: try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0021"),
            capturedAt: now
        )
        let middleAnchor = makeAnchor(
            extensionId: "middle",
            profileId: profileId,
            sessionToken: try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0022"),
            capturedAt: now.addingTimeInterval(1)
        )
        let newestAnchor = makeAnchor(
            extensionId: "newest",
            profileId: profileId,
            sessionToken: try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0023"),
            capturedAt: now.addingTimeInterval(2)
        )
        let store = ExtensionActionPopupAnchorStore(
            sessionTTL: 60,
            pendingLimit: 2
        )

        store.store(oldestAnchor, now: now)
        store.store(middleAnchor, now: now)
        store.store(newestAnchor, now: now)

        XCTAssertEqual(store.pendingCount, 2)
        XCTAssertFalse(store.contains(sessionToken: oldestAnchor.sessionToken))
        XCTAssertTrue(store.contains(sessionToken: middleAnchor.sessionToken))
        XCTAssertTrue(store.contains(sessionToken: newestAnchor.sessionToken))
        XCTAssertNil(store.latestSessionToken(for: "oldest"))
    }

    func testAnchorStoreClearsMismatchedProfilesAndConsumesSessions() throws {
        let profileA = try uuid("11111111-2222-3333-4444-555555555555")
        let profileB = try uuid("66666666-7777-8888-9999-AAAAAAAAAAAA")
        let profileAAnchor = makeAnchor(
            extensionId: "profile-a",
            profileId: profileA,
            sessionToken: try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0031")
        )
        let profileBAnchor = makeAnchor(
            extensionId: "profile-b",
            profileId: profileB,
            sessionToken: try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0032")
        )
        let store = ExtensionActionPopupAnchorStore()

        store.store(profileAAnchor)
        store.store(profileBAnchor)
        store.clearAnchors(notMatching: profileA)

        XCTAssertTrue(store.contains(sessionToken: profileAAnchor.sessionToken))
        XCTAssertFalse(store.contains(sessionToken: profileBAnchor.sessionToken))
        XCTAssertNil(store.latestSessionToken(for: "profile-b"))

        store.consume(sessionToken: profileAAnchor.sessionToken)
        XCTAssertFalse(store.contains(sessionToken: profileAAnchor.sessionToken))
        XCTAssertNil(store.latestSessionToken(for: "profile-a"))
        XCTAssertEqual(store.pendingCount, 0)
    }

    private func makeAnchor(
        extensionId: String,
        profileId: UUID,
        windowId: UUID = UUID(),
        sessionToken: UUID,
        capturedAt: Date = Date()
    ) -> ExtensionActionPopupAnchor {
        ExtensionActionPopupAnchor(
            extensionID: extensionId,
            profileID: profileId,
            windowID: windowId,
            sessionToken: sessionToken,
            capturedAt: capturedAt,
            buttonView: nil,
            validatedRectInWindow: nil
        )
    }

    private func uuid(_ string: String) throws -> UUID {
        try XCTUnwrap(UUID(uuidString: string))
    }

    private func projectURL(_ relativePath: String) -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(relativePath)
    }
}
