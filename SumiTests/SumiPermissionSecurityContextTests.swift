import XCTest

@testable import Sumi

final class SumiPermissionSecurityContextTests: XCTestCase {
    func testConstructsFromPermissionRequest() {
        let requestedAt = date("2026-04-28T08:00:00Z")
        let now = date("2026-04-28T08:01:00Z")
        let request = SumiPermissionRequest(
            id: "request-a",
            tabId: "tab-a",
            pageId: "page-a",
            frameId: "frame-a",
            requestingOrigin: SumiPermissionOrigin(string: "https://camera.example/path"),
            topOrigin: SumiPermissionOrigin(string: "https://top.example"),
            permissionTypes: [.camera],
            hasUserGesture: true,
            requestedAt: requestedAt,
            isEphemeralProfile: false,
            profilePartitionId: " Profile-A "
        )

        let context = SumiPermissionSecurityContext(
            request: request,
            committedURL: URL(string: "https://camera.example/path"),
            visibleURL: URL(string: "https://camera.example/visible"),
            mainFrameURL: URL(string: "https://camera.example/main"),
            surface: .normalTab,
            navigationOrPageGeneration: "generation-a",
            now: now
        )

        XCTAssertEqual(context.request, request)
        XCTAssertEqual(context.requestingOrigin.identity, "https://camera.example")
        XCTAssertEqual(context.topOrigin.identity, "https://top.example")
        XCTAssertEqual(context.committedURL?.absoluteString, "https://camera.example/path")
        XCTAssertEqual(context.visibleURL?.absoluteString, "https://camera.example/visible")
        XCTAssertEqual(context.mainFrameURL?.absoluteString, "https://camera.example/main")
        XCTAssertTrue(context.isMainFrame)
        XCTAssertTrue(context.isActiveTab)
        XCTAssertTrue(context.isVisibleTab)
        XCTAssertEqual(context.hasUserGesture, true)
        XCTAssertFalse(context.isEphemeralProfile)
        XCTAssertEqual(context.profilePartitionId, "profile-a")
        XCTAssertEqual(context.transientPageId, "page-a")
        XCTAssertEqual(context.surface, .normalTab)
        XCTAssertEqual(context.navigationOrPageGeneration, "generation-a")
        XCTAssertEqual(context.now, now)
    }

    func testCommittedAndVisibleURLsRemainDistinct() {
        let request = permissionRequest()

        let context = SumiPermissionSecurityContext(
            request: request,
            committedURL: URL(string: "https://real.example"),
            visibleURL: URL(string: "https://shown.example"),
            mainFrameURL: URL(string: "https://real.example"),
            now: date("2026-04-28T08:00:00Z")
        )

        XCTAssertEqual(context.committedURL?.host, "real.example")
        XCTAssertEqual(context.visibleURL?.host, "shown.example")
        XCTAssertNotEqual(
            SumiPermissionOrigin(url: context.committedURL).identity,
            SumiPermissionOrigin(url: context.visibleURL).identity
        )
    }

    func testFullInitializerAllowsUnknownUserGesture() {
        let request = permissionRequest(hasUserGesture: true)
        let now = date("2026-04-28T08:00:00Z")

        let context = SumiPermissionSecurityContext(
            request: request,
            requestingOrigin: request.requestingOrigin,
            topOrigin: request.topOrigin,
            committedURL: nil,
            visibleURL: nil,
            mainFrameURL: nil,
            isMainFrame: false,
            isActiveTab: false,
            isVisibleTab: false,
            hasUserGesture: nil,
            isEphemeralProfile: true,
            profilePartitionId: "Ephemeral-A",
            transientPageId: " transient-page ",
            surface: .glance,
            navigationOrPageGeneration: " generation-b ",
            now: now
        )

        XCTAssertNil(context.hasUserGesture)
        XCTAssertFalse(context.isMainFrame)
        XCTAssertFalse(context.isActiveTab)
        XCTAssertFalse(context.isVisibleTab)
        XCTAssertTrue(context.isEphemeralProfile)
        XCTAssertEqual(context.profilePartitionId, "ephemeral-a")
        XCTAssertEqual(context.transientPageId, "transient-page")
        XCTAssertEqual(context.surface, .glance)
        XCTAssertEqual(context.navigationOrPageGeneration, "generation-b")
    }

    func testProfileAndTransientFieldsUseRequestDefaults() {
        let request = SumiPermissionRequest(
            tabId: "tab-fallback",
            pageId: nil,
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionTypes: [.notifications],
            isEphemeralProfile: true,
            profilePartitionId: " Mixed-Case-Profile "
        )

        let context = SumiPermissionSecurityContext(request: request)

        XCTAssertTrue(context.isEphemeralProfile)
        XCTAssertEqual(context.profilePartitionId, "mixed-case-profile")
        XCTAssertEqual(context.transientPageId, "tab-fallback")
    }

    func testDisplayDomainDoesNotReplaceSecurityOrigins() {
        let request = SumiPermissionRequest(
            requestingOrigin: SumiPermissionOrigin(string: "http://evil.example"),
            topOrigin: SumiPermissionOrigin(string: "http://evil.example"),
            displayDomain: "trusted.example",
            permissionTypes: [.camera],
            profilePartitionId: "profile-a"
        )

        let context = SumiPermissionSecurityContext(request: request)

        XCTAssertEqual(context.request.displayDomain, "trusted.example")
        XCTAssertEqual(context.requestingOrigin.identity, "http://evil.example")
        XCTAssertEqual(context.topOrigin.identity, "http://evil.example")
    }

    private func permissionRequest(
        hasUserGesture: Bool = false
    ) -> SumiPermissionRequest {
        SumiPermissionRequest(
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionTypes: [.camera],
            hasUserGesture: hasUserGesture,
            profilePartitionId: "profile-a"
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
