import XCTest

@testable import Sumi

final class SumiSystemPermissionServiceScreenCaptureTests: XCTestCase {
    func testFakeScreenCaptureStates() async {
        for state in SumiSystemPermissionAuthorizationState.allCases {
            let service = FakeSumiSystemPermissionService(states: [.screenCapture: state])
            let snapshot = await service.authorizationSnapshot(for: .screenCapture)

            XCTAssertEqual(snapshot.kind, .screenCapture)
            XCTAssertEqual(snapshot.state, state)
            XCTAssertEqual(snapshot.canRequestFromSystem, state == .notDetermined)
            XCTAssertEqual(
                snapshot.shouldOpenSystemSettings,
                [.denied, .restricted, .systemDisabled].contains(state)
            )
            XCTAssertFalse(snapshot.reason.isEmpty)
        }
    }

    func testCoreGraphicsPreflightMapperIsReadOnlyAndAmbiguousWhenFalse() {
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.screenCapturePreflight(isAuthorized: true),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.screenCapturePreflight(isAuthorized: false),
            .notDetermined
        )
    }

    func testCoreGraphicsRequestMapperIsForFuturePromptUIOnly() {
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.screenCaptureRequest(granted: true),
            .authorized
        )
        XCTAssertEqual(
            SumiSystemPermissionAuthorizationMapper.screenCaptureRequest(granted: false),
            .denied
        )
    }

    func testMacScreenCaptureSnapshotUsesPreflightAndDeterministicLimitationReason() async {
        let authorized = MacSumiSystemPermissionService(
            screenCapturePreflightAccess: { true },
            requestScreenCaptureAccess: { XCTFail("request should not be called by snapshot"); return false }
        )
        let authorizedSnapshot = await authorized.authorizationSnapshot(for: .screenCapture)
        XCTAssertEqual(authorizedSnapshot.state, .authorized)
        XCTAssertFalse(authorizedSnapshot.canRequestFromSystem)

        let notDetermined = MacSumiSystemPermissionService(
            screenCapturePreflightAccess: { false },
            requestScreenCaptureAccess: { XCTFail("request should not be called by snapshot"); return false }
        )
        let notDeterminedSnapshot = await notDetermined.authorizationSnapshot(for: .screenCapture)
        XCTAssertEqual(notDeterminedSnapshot.state, .notDetermined)
        XCTAssertTrue(notDeterminedSnapshot.canRequestFromSystem)
        XCTAssertTrue(notDeterminedSnapshot.reason.contains("cannot distinguish"))
    }

    func testMacScreenCaptureRequestUsesInjectedRequestClosureOnlyWhenNotDetermined() async {
        let requestCallCount = SumiScreenCaptureRequestCounter()
        let service = MacSumiSystemPermissionService(
            screenCapturePreflightAccess: { false },
            requestScreenCaptureAccess: {
                requestCallCount.increment()
                return true
            }
        )

        let state = await service.requestAuthorization(for: .screenCapture)

        XCTAssertEqual(state, .authorized)
        XCTAssertEqual(requestCallCount.count, 1)
    }

    func testScreenCaptureSystemSettingsLinkIsBestEffort() {
        let url = SumiSystemPermissionSettingsLink.url(for: .screenCapture)

        XCTAssertEqual(
            url?.absoluteString,
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture"
        )
    }

    func testResolverCallsSnapshotOnlyAndNeverRequestsSystemAuthorization() async {
        let service = FakeSumiSystemPermissionService(states: [.screenCapture: .authorized])
        let request = SumiPermissionRequest(
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionTypes: [.screenCapture],
            profilePartitionId: "profile-a"
        )
        let resolver = DefaultSumiPermissionPolicyResolver(systemPermissionService: service)

        _ = await resolver.evaluate(SumiPermissionSecurityContext(
            request: request,
            requestingOrigin: request.requestingOrigin,
            topOrigin: request.topOrigin,
            committedURL: URL(string: "https://example.com"),
            visibleURL: URL(string: "https://example.com"),
            mainFrameURL: URL(string: "https://example.com"),
            isMainFrame: true,
            isActiveTab: true,
            isVisibleTab: true,
            hasUserGesture: false,
            isEphemeralProfile: false,
            profilePartitionId: "profile-a",
            transientPageId: nil,
            surface: .normalTab,
            navigationOrPageGeneration: nil,
            now: Date()
        ))

        let requestAuthorizationCallCount = await service.requestAuthorizationCallCount(for: .screenCapture)
        XCTAssertEqual(requestAuthorizationCallCount, 0)
    }
}

private final class SumiScreenCaptureRequestCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var value = 0

    func increment() {
        lock.withLock {
            value += 1
        }
    }

    var count: Int {
        lock.withLock { value }
    }
}
