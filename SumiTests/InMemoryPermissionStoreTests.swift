import XCTest

@testable import Sumi

final class InMemoryPermissionStoreTests: XCTestCase {
    func testOneTimeDecisionLookup() async throws {
        let store = InMemoryPermissionStore()
        let permissionKey = key(.filePicker, pageId: "page-a")
        try await store.setDecision(for: permissionKey, decision: decision(.allow, persistence: .oneTime))

        let record = try await store.getDecision(for: permissionKey)

        XCTAssertEqual(record?.decision.state, .allow)
        XCTAssertEqual(record?.decision.persistence, .oneTime)
    }

    func testSessionDecisionLookup() async throws {
        let store = InMemoryPermissionStore()
        let permissionKey = key(.camera)
        try await store.setDecision(
            for: permissionKey,
            decision: decision(.allow, persistence: .session),
            sessionOwnerId: "window-a"
        )

        let matching = try await store.getDecision(for: permissionKey, sessionOwnerId: "window-a")
        let otherWindow = try await store.getDecision(for: permissionKey, sessionOwnerId: "window-b")

        XCTAssertEqual(matching?.decision.state, .allow)
        XCTAssertNil(otherWindow)
    }

    func testExpiration() async throws {
        let store = InMemoryPermissionStore()
        let permissionKey = key(.camera)
        try await store.setDecision(
            for: permissionKey,
            decision: decision(
                .allow,
                persistence: .session,
                expiresAt: date("2026-04-28T09:00:00Z")
            )
        )

        let expiredCount = try await store.expireDecisions(now: date("2026-04-28T10:00:00Z"))
        let record = try await store.getDecision(for: permissionKey)

        XCTAssertEqual(expiredCount, 1)
        XCTAssertNil(record)
    }

    func testClearByPageId() async throws {
        let store = InMemoryPermissionStore()
        let permissionKey = key(.filePicker, pageId: "page-a")
        try await store.setDecision(for: permissionKey, decision: decision(.allow, persistence: .oneTime))

        let cleared = await store.clearForPageId("page-a")
        let record = try await store.getDecision(for: permissionKey)

        XCTAssertEqual(cleared, 1)
        XCTAssertNil(record)
    }

    func testClearByProfileAndSession() async throws {
        let store = InMemoryPermissionStore()
        let sessionKey = key(.camera, profile: "profile-a")
        let oneTimeKey = key(.filePicker, profile: "profile-b", pageId: "page-b")
        try await store.setDecision(
            for: sessionKey,
            decision: decision(.allow, persistence: .session),
            sessionOwnerId: "window-a"
        )
        try await store.setDecision(
            for: oneTimeKey,
            decision: decision(.allow, persistence: .oneTime)
        )

        let sessionCleared = await store.clearForSession(ownerId: "window-a")
        let clearedSessionRecord = try await store.getDecision(
            for: sessionKey,
            sessionOwnerId: "window-a"
        )
        XCTAssertEqual(sessionCleared, 1)
        XCTAssertNil(clearedSessionRecord)

        let profileCleared = await store.clearForProfile(profilePartitionId: "profile-b")
        let clearedOneTimeRecord = try await store.getDecision(for: oneTimeKey)
        XCTAssertEqual(profileCleared, 1)
        XCTAssertNil(clearedOneTimeRecord)
    }

    private func key(
        _ type: SumiPermissionType,
        profile: String = "profile-a",
        pageId: String? = nil
    ) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionType: type,
            profilePartitionId: profile,
            transientPageId: pageId
        )
    }

    private func decision(
        _ state: SumiPermissionState,
        persistence: SumiPermissionPersistence,
        expiresAt: Date? = nil
    ) -> SumiPermissionDecision {
        SumiPermissionDecision(
            state: state,
            persistence: persistence,
            source: .user,
            createdAt: date("2026-04-28T08:00:00Z"),
            updatedAt: date("2026-04-28T08:00:00Z"),
            expiresAt: expiresAt
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
