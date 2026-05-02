import XCTest

@testable import Sumi

final class SumiPermissionSessionLifecycleTests: XCTestCase {
    func testSessionGrantSurvivesPageChangeAndClearsOnProfileCleanup() async {
        let coordinator = SumiPermissionCoordinator(
            policyResolver: SessionLifecyclePolicyResolver(),
            persistentStore: SessionLifecyclePersistentStore(),
            sessionOwnerId: "browser",
            now: sessionLifecycleDate
        )

        let task = Task {
            await coordinator.requestPermission(
                sessionContext(.camera, id: "camera-session", pageId: "tab-a:1")
            )
        }
        let query = await waitForSessionLifecycleActiveQuery(coordinator, pageId: "tab-a:1")
        await coordinator.approveForSession(query.id)
        let first = await task.value

        let otherPage = await coordinator.requestPermission(
            sessionContext(.camera, id: "camera-other-page", pageId: "tab-a:2")
        )
        await coordinator.cancelProfile(profilePartitionId: "profile-a")
        let afterCleanup = await coordinator.queryPermissionState(
            sessionContext(.camera, id: "camera-after-cleanup", pageId: "tab-a:3")
        )

        XCTAssertEqual(first.outcome, .granted)
        XCTAssertEqual(first.persistence, .session)
        XCTAssertEqual(otherPage.outcome, .granted)
        XCTAssertEqual(otherPage.persistence, .session)
        XCTAssertEqual(afterCleanup.outcome, .promptRequired)
    }

    func testEphemeralPersistentApprovalDowngradesToSessionAndDoesNotWriteSwiftDataStore() async {
        let persistentStore = SessionLifecyclePersistentStore()
        let coordinator = SumiPermissionCoordinator(
            policyResolver: SessionLifecyclePolicyResolver(),
            persistentStore: persistentStore,
            sessionOwnerId: "browser",
            now: sessionLifecycleDate
        )

        let task = Task {
            await coordinator.requestPermission(
                sessionContext(
                    .microphone,
                    id: "ephemeral-microphone",
                    pageId: "tab-a:1",
                    isEphemeralProfile: true
                )
            )
        }
        let query = await waitForSessionLifecycleActiveQuery(coordinator, pageId: "tab-a:1")
        await coordinator.approvePersistently(query.id)
        let decision = await task.value
        let persistentWrites = await persistentStore.setDecisionCount

        XCTAssertEqual(decision.outcome, .granted)
        XCTAssertEqual(decision.persistence, .session)
        XCTAssertEqual(persistentWrites, 0)
    }
}

private actor SessionLifecyclePolicyResolver: SumiPermissionPolicyResolver {
    func evaluate(_ context: SumiPermissionSecurityContext) async -> SumiPermissionPolicyResult {
        .proceed(
            source: .defaultSetting,
            reason: SumiPermissionPolicyReason.allowed,
            systemAuthorizationSnapshot: nil,
            mayOpenSystemSettings: false,
            allowedPersistences: context.isEphemeralProfile ? [.oneTime, .session] : [.oneTime, .session, .persistent]
        )
    }
}

private actor SessionLifecyclePersistentStore: SumiPermissionStore {
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

private func sessionContext(
    _ permissionType: SumiPermissionType,
    id: String,
    pageId: String,
    isEphemeralProfile: Bool = false
) -> SumiPermissionSecurityContext {
    let request = SumiPermissionRequest(
        id: id,
        tabId: "tab-a",
        pageId: pageId,
        requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
        topOrigin: SumiPermissionOrigin(string: "https://example.com"),
        permissionTypes: [permissionType],
        requestedAt: sessionLifecycleDate(),
        isEphemeralProfile: isEphemeralProfile,
        profilePartitionId: "profile-a"
    )
    return SumiPermissionSecurityContext(
        request: request,
        committedURL: URL(string: "https://example.com"),
        visibleURL: URL(string: "https://example.com"),
        mainFrameURL: URL(string: "https://example.com"),
        isEphemeralProfile: isEphemeralProfile,
        transientPageId: pageId,
        now: sessionLifecycleDate()
    )
}

private func waitForSessionLifecycleActiveQuery(
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
        createdAt: sessionLifecycleDate(),
        isEphemeralProfile: false,
        shouldOfferSystemSettings: false,
        disablesPersistentAllow: false,
    )
}

private func sessionLifecycleDate() -> Date {
    ISO8601DateFormatter().date(from: "2026-04-28T10:00:00Z")!
}
