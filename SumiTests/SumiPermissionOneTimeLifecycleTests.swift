import XCTest

@testable import Sumi

final class SumiPermissionOneTimeLifecycleTests: XCTestCase {
    func testAllowThisTimeReusesSamePageAndRepromptsOnNewPage() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: OneTimeLifecyclePolicyResolver(),
            persistentStore: OneTimeLifecyclePersistentStore(),
            now: fixedPermissionLifecycleDate
        )

        let first = Task {
            await coordinator.requestPermission(context(.camera, id: "camera-first", pageId: "tab-a:1"))
        }
        let query = await waitForLifecycleActiveQuery(coordinator, pageId: "tab-a:1")
        await coordinator.approveOnce(query.id)
        let firstDecision = await first.value

        let samePage = await coordinator.requestPermission(
            context(.camera, id: "camera-repeat", pageId: "tab-a:1")
        )
        let newPage = await coordinator.queryPermissionState(
            context(.camera, id: "camera-new-page", pageId: "tab-a:2")
        )

        XCTAssertEqual(firstDecision.outcome, .granted)
        XCTAssertEqual(firstDecision.persistence, .oneTime)
        XCTAssertEqual(samePage.outcome, .granted)
        XCTAssertEqual(samePage.persistence, .oneTime)
        XCTAssertEqual(newPage.outcome, .promptRequired)
    }

    func testCameraAndMicrophoneAllowThisTimeCreatesConcreteOneTimeGrants() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: OneTimeLifecyclePolicyResolver(),
            persistentStore: OneTimeLifecyclePersistentStore(),
            now: fixedPermissionLifecycleDate
        )

        let grouped = Task {
            await coordinator.requestPermission(
                context(permissionTypes: [.camera, .microphone], id: "grouped", pageId: "tab-a:1")
            )
        }
        let query = await waitForLifecycleActiveQuery(coordinator, pageId: "tab-a:1")
        await coordinator.approveOnce(query.id)
        _ = await grouped.value

        let camera = await coordinator.requestPermission(
            context(.camera, id: "camera-repeat", pageId: "tab-a:1")
        )
        let microphone = await coordinator.requestPermission(
            context(.microphone, id: "microphone-repeat", pageId: "tab-a:1")
        )

        XCTAssertEqual(camera.outcome, .granted)
        XCTAssertEqual(camera.persistence, .oneTime)
        XCTAssertEqual(microphone.outcome, .granted)
        XCTAssertEqual(microphone.persistence, .oneTime)
    }

    func testExternalOpenThisTimeDoesNotCreateReusableOneTimeGrant() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: OneTimeLifecyclePolicyResolver(),
            persistentStore: OneTimeLifecyclePersistentStore(),
            now: fixedPermissionLifecycleDate
        )
        let permissionType = SumiPermissionType.externalScheme("mailto")

        let first = Task {
            await coordinator.requestPermission(
                context(permissionType, id: "mailto-first", pageId: "tab-a:1", hasUserGesture: true)
            )
        }
        let query = await waitForLifecycleActiveQuery(coordinator, pageId: "tab-a:1")
        let settlement = await coordinator.approveCurrentAttempt(query.id)
        let firstDecision = await first.value
        let repeated = await coordinator.queryPermissionState(
            context(permissionType, id: "mailto-repeat", pageId: "tab-a:1", hasUserGesture: true)
        )

        XCTAssertEqual(settlement.outcome, .granted)
        XCTAssertNil(settlement.persistence)
        XCTAssertEqual(firstDecision.outcome, .granted)
        XCTAssertNil(firstDecision.persistence)
        XCTAssertEqual(repeated.outcome, .promptRequired)
    }
}

private actor OneTimeLifecyclePolicyResolver: SumiPermissionPolicyResolver {
    func evaluate(_ context: SumiPermissionSecurityContext) async -> SumiPermissionPolicyResult {
        let permissionType = context.request.permissionTypes.first ?? .camera
        return .proceed(
            source: .defaultSetting,
            reason: SumiPermissionPolicyReason.allowed,
            systemAuthorizationSnapshot: nil,
            mayOpenSystemSettings: false,
            allowedPersistences: [.oneTime, .session, .persistent]
        )
    }
}

private actor OneTimeLifecyclePersistentStore: SumiPermissionStore {
    private var records: [String: SumiPermissionStoreRecord] = [:]
    private(set) var setDecisionCount = 0

    func getDecision(for key: SumiPermissionKey) async throws -> SumiPermissionStoreRecord? {
        records[key.persistentIdentity]
    }

    func setDecision(for key: SumiPermissionKey, decision: SumiPermissionDecision) async throws {
        setDecisionCount += 1
        records[key.persistentIdentity] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func resetDecision(for key: SumiPermissionKey) async throws {
        records.removeValue(forKey: key.persistentIdentity)
    }

    func listDecisions(profilePartitionId: String) async throws -> [SumiPermissionStoreRecord] {
        records.values.filter { $0.key.profilePartitionId == profilePartitionId }
    }

    func listDecisions(
        forDisplayDomain displayDomain: String,
        profilePartitionId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        try await listDecisions(profilePartitionId: profilePartitionId)
            .filter { $0.displayDomain == displayDomain }
    }

    func clearAll(profilePartitionId: String) async throws {
        records = records.filter { _, record in record.key.profilePartitionId != profilePartitionId }
    }

    func clearForDisplayDomains(_ displayDomains: Set<String>, profilePartitionId: String) async throws {}

    func clearForOrigins(_ origins: Set<SumiPermissionOrigin>, profilePartitionId: String) async throws {}

    @discardableResult
    func expireDecisions(now: Date) async throws -> Int { 0 }

    func recordLastUsed(for key: SumiPermissionKey, at date: Date) async throws {}
}

private func context(
    _ permissionType: SumiPermissionType,
    id: String,
    pageId: String,
    hasUserGesture: Bool = true
) -> SumiPermissionSecurityContext {
    context(
        permissionTypes: [permissionType],
        id: id,
        pageId: pageId,
        hasUserGesture: hasUserGesture
    )
}

private func context(
    permissionTypes: [SumiPermissionType],
    id: String,
    pageId: String,
    hasUserGesture: Bool = true
) -> SumiPermissionSecurityContext {
    let request = SumiPermissionRequest(
        id: id,
        tabId: "tab-a",
        pageId: pageId,
        requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
        topOrigin: SumiPermissionOrigin(string: "https://example.com"),
        permissionTypes: permissionTypes,
        requestedAt: fixedPermissionLifecycleDate(),
        profilePartitionId: "profile-a"
    )
    return SumiPermissionSecurityContext(
        request: request,
        committedURL: URL(string: "https://example.com"),
        visibleURL: URL(string: "https://example.com"),
        mainFrameURL: URL(string: "https://example.com"),
        transientPageId: pageId,
        now: fixedPermissionLifecycleDate()
    )
}

private func waitForLifecycleActiveQuery(
    _ coordinator: SumiPermissionCoordinator,
    pageId: String,
    file: StaticString = #filePath,
    line: UInt = #line
) async -> SumiPermissionAuthorizationQuery {
    for _ in 0..<100 {
        if let query = await coordinator.activeQuery(forPageId: pageId) {
            return query
        }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    XCTFail("Timed out waiting for permission query", file: file, line: line)
    return SumiPermissionAuthorizationQuery(
        id: "missing",
        pageId: pageId,
        profilePartitionId: "profile-a",
        displayDomain: "missing",
        requestingOrigin: .invalid(),
        topOrigin: .invalid(),
        permissionTypes: [],
        presentationPermissionType: nil,
        availablePersistences: [],
        systemAuthorizationSnapshots: [],
        policyReasons: [],
        createdAt: fixedPermissionLifecycleDate(),
        isEphemeralProfile: false,
        shouldOfferSystemSettings: false,
        disablesPersistentAllow: false,
    )
}

private func fixedPermissionLifecycleDate() -> Date {
    ISO8601DateFormatter().date(from: "2026-04-28T10:00:00Z")!
}
