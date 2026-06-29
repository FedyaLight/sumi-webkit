import AppKit
import XCTest

@testable import Sumi

@available(macOS 15.5, *)
@MainActor
final class SafariExtensionActionPopupAnchorTests: XCTestCase {
    func testAnchorModelCapturesExtensionProfileWindowSessionAndWeakButton() throws {
        let profileId = try uuid("11111111-2222-3333-4444-555555555555")
        let windowId = try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEEEEE1")
        let sessionToken = try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0001")
        let buttonView = NSView(frame: NSRect(x: 10, y: 20, width: 30, height: 40))

        let anchor = ExtensionActionPopupAnchor(
            extensionID: "tracked-extension",
            profileID: profileId,
            windowID: windowId,
            sessionToken: sessionToken,
            capturedAt: Date(timeIntervalSince1970: 1_000),
            buttonView: buttonView,
            validatedRectInWindow: NSRect(x: 1, y: 2, width: 3, height: 4)
        )

        XCTAssertEqual(anchor.extensionID, "tracked-extension")
        XCTAssertEqual(anchor.profileID, profileId)
        XCTAssertEqual(anchor.windowID, windowId)
        XCTAssertEqual(anchor.sessionToken, sessionToken)
        XCTAssertIdentical(anchor.buttonView, buttonView)
        XCTAssertEqual(
            anchor.validatedRectInWindow,
            NSRect(x: 1, y: 2, width: 3, height: 4)
        )
    }

    func testAnchorResolutionTraceLineReportsSanitizedState() throws {
        let sessionToken = try uuid("AAAAAAAA-BBBB-CCCC-DDDD-EEEEEEEE0002")
        let resolution = ExtensionActionPopupAnchorResolution(
            anchorResolved: true,
            anchorSource: .fallback,
            windowMatch: true,
            profileMatch: false,
            sessionToken: sessionToken
        )

        XCTAssertEqual(
            resolution.traceLine,
            "anchorResolved=true anchorSource=fallback windowMatch=true profileMatch=false sessionToken=\(sessionToken.uuidString)"
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
}
