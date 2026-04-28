import XCTest

@testable import Sumi

final class SumiStorageAccessPolicyTests: XCTestCase {
    func testCrossOriginSecureNormalTabStorageAccessIsSupported() async {
        let result = await evaluateStorageAccess()

        XCTAssertTrue(result.isAllowedToProceed)
        XCTAssertTrue(result.mayAskUser)
        XCTAssertEqual(result.source, .defaultSetting)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.allowed)
        XCTAssertTrue(result.allowedPersistences.contains(.persistent))
    }

    func testEphemeralStorageAccessExcludesPersistentChoices() async {
        let result = await evaluateStorageAccess(isEphemeralProfile: true)

        XCTAssertTrue(result.isAllowedToProceed)
        XCTAssertEqual(result.allowedPersistences, [.oneTime, .session])
        XCTAssertFalse(result.allowedPersistences.contains(.persistent))
    }

    func testSameOriginStorageAccessFailsClosed() async {
        let result = await evaluateStorageAccess(
            requestingOrigin: SumiPermissionOrigin(string: "https://rp.example"),
            topOrigin: SumiPermissionOrigin(string: "https://rp.example")
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .defaultSetting)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.storageAccessSameOrigin)
        XCTAssertFalse(result.mayAskUser)
    }

    func testInsecureRequestingOriginFailsClosed() async {
        let result = await evaluateStorageAccess(
            requestingOrigin: SumiPermissionOrigin(string: "http://idp.example")
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .insecureOrigin)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.insecureRequestingOrigin)
    }

    func testInsecureTopOriginFailsClosed() async {
        let result = await evaluateStorageAccess(
            topOrigin: SumiPermissionOrigin(string: "http://rp.example"),
            committedURL: URL(string: "http://rp.example"),
            visibleURL: URL(string: "http://rp.example")
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .insecureOrigin)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.insecureTopOrigin)
    }

    func testMissingTrustedOriginFailsClosed() async {
        let result = await evaluateStorageAccess(
            requestingOrigin: .invalid(reason: "missing-requesting-origin")
        )

        XCTAssertFalse(result.isAllowedToProceed)
        XCTAssertEqual(result.source, .invalidOrigin)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.invalidRequestingOrigin)
    }

    func testStorageAccessDoesNotRequireUserActivationFromPrivateSelector() async {
        let result = await evaluateStorageAccess(hasUserGesture: nil)

        XCTAssertTrue(result.isAllowedToProceed)
        XCTAssertEqual(result.reason, SumiPermissionPolicyReason.allowed)
    }

    func testStorageAccessRequiresNormalTabSurface() async {
        let miniWindow = await evaluateStorageAccess(surface: .miniWindow)
        XCTAssertFalse(miniWindow.isAllowedToProceed)
        XCTAssertEqual(miniWindow.reason, SumiPermissionPolicyReason.miniWindowSensitiveDenied)

        let peek = await evaluateStorageAccess(surface: .peek)
        XCTAssertFalse(peek.isAllowedToProceed)
        XCTAssertEqual(peek.reason, SumiPermissionPolicyReason.peekSensitiveDenied)
    }

    private func evaluateStorageAccess(
        requestingOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://idp.example"),
        topOrigin: SumiPermissionOrigin = SumiPermissionOrigin(string: "https://rp.example"),
        committedURL: URL? = URL(string: "https://rp.example/page"),
        visibleURL: URL? = URL(string: "https://rp.example/page"),
        surface: SumiPermissionSecurityContext.Surface = .normalTab,
        hasUserGesture: Bool? = false,
        isEphemeralProfile: Bool = false
    ) async -> SumiPermissionPolicyResult {
        let request = SumiPermissionRequest(
            id: "storage-access-a",
            tabId: "tab-a",
            pageId: "tab-a:1",
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            displayDomain: requestingOrigin.displayDomain,
            permissionTypes: [.storageAccess],
            hasUserGesture: hasUserGesture ?? false,
            requestedAt: date("2026-04-28T09:00:00Z"),
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: "profile-a"
        )
        let context = SumiPermissionSecurityContext(
            request: request,
            requestingOrigin: requestingOrigin,
            topOrigin: topOrigin,
            committedURL: committedURL,
            visibleURL: visibleURL,
            mainFrameURL: committedURL,
            isMainFrame: false,
            isActiveTab: true,
            isVisibleTab: true,
            hasUserGesture: hasUserGesture,
            isEphemeralProfile: isEphemeralProfile,
            profilePartitionId: "profile-a",
            transientPageId: "tab-a:1",
            surface: surface,
            navigationOrPageGeneration: "1",
            now: date("2026-04-28T09:00:01Z")
        )
        let resolver = DefaultSumiPermissionPolicyResolver(
            systemPermissionService: FakeSumiSystemPermissionService()
        )
        return await resolver.evaluate(context)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
