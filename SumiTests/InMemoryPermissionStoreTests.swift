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

    func testOneTimeDecisionDoesNotMatchDifferentOriginForSamePageOwner() async throws {
        let store = InMemoryPermissionStore()
        let allowedKey = key(.camera, requestingOrigin: "https://example.com", pageId: "tab-a:1")
        let otherOriginKey = key(.camera, requestingOrigin: "https://other.example", pageId: "tab-a:1")
        try await store.setDecision(
            for: allowedKey,
            decision: decision(.allow, persistence: .oneTime)
        )

        let exactRecord = try await store.getDecision(for: allowedKey)
        let otherOriginRecord = try await store.getDecision(for: otherOriginKey)

        XCTAssertEqual(exactRecord?.key, allowedKey)
        XCTAssertNil(otherOriginRecord)
    }

    func testSessionDecisionDoesNotMatchDifferentPermissionTypeForSameOwner() async throws {
        let store = InMemoryPermissionStore()
        let cameraKey = key(.camera)
        let microphoneKey = key(.microphone)
        try await store.setDecision(
            for: cameraKey,
            decision: decision(.allow, persistence: .session),
            sessionOwnerId: "window-a"
        )

        let exactRecord = try await store.getDecision(for: cameraKey, sessionOwnerId: "window-a")
        let otherPermissionRecord = try await store.getDecision(for: microphoneKey, sessionOwnerId: "window-a")

        XCTAssertEqual(exactRecord?.key, cameraKey)
        XCTAssertNil(otherPermissionRecord)
    }

    func testSessionDecisionDoesNotMatchDifferentProfileForSameOwner() async throws {
        let store = InMemoryPermissionStore()
        let profileAKey = key(.camera, profile: "profile-a")
        let profileBKey = key(.camera, profile: "profile-b")
        try await store.setDecision(
            for: profileAKey,
            decision: decision(.allow, persistence: .session),
            sessionOwnerId: "window-a"
        )

        let exactRecord = try await store.getDecision(for: profileAKey, sessionOwnerId: "window-a")
        let otherProfileRecord = try await store.getDecision(for: profileBKey, sessionOwnerId: "window-a")

        XCTAssertEqual(exactRecord?.key, profileAKey)
        XCTAssertNil(otherProfileRecord)
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

    func testOneTimeDecisionRequiresPageIdAndDoesNotMatchOtherPageId() async throws {
        let store = InMemoryPermissionStore()
        let pageAKey = key(.camera, pageId: "tab-a:1")
        let pageBKey = key(.camera, pageId: "tab-a:2")

        await XCTAssertThrowsErrorAsync {
            try await store.setDecision(
                for: key(.camera),
                decision: decision(.allow, persistence: .oneTime)
            )
        }

        try await store.setDecision(
            for: pageAKey,
            decision: decision(.allow, persistence: .oneTime)
        )

        let pageARecord = try await store.getDecision(for: pageAKey)
        let pageBRecord = try await store.getDecision(for: pageBKey)
        XCTAssertNotNil(pageARecord)
        XCTAssertNil(pageBRecord)
    }

    func testClearOneTimeDecisionsForTabIdClearsAllPageGenerations() async throws {
        let store = InMemoryPermissionStore()
        let pageAKey = key(.camera, pageId: "tab-a:1")
        let pageBKey = key(.microphone, pageId: "tab-a:2")
        let otherTabKey = key(.camera, pageId: "tab-b:1")
        try await store.setDecision(for: pageAKey, decision: decision(.allow, persistence: .oneTime))
        try await store.setDecision(for: pageBKey, decision: decision(.allow, persistence: .oneTime))
        try await store.setDecision(for: otherTabKey, decision: decision(.allow, persistence: .oneTime))

        let cleared = await store.clearOneTimeDecisions(forTabId: "tab-a")
        let pageARecord = try await store.getDecision(for: pageAKey)
        let pageBRecord = try await store.getDecision(for: pageBKey)
        let otherTabRecord = try await store.getDecision(for: otherTabKey)

        XCTAssertEqual(cleared, 2)
        XCTAssertNil(pageARecord)
        XCTAssertNil(pageBRecord)
        XCTAssertNotNil(otherTabRecord)
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
        requestingOrigin: String = "https://example.com",
        topOrigin: String? = nil,
        pageId: String? = nil
    ) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: requestingOrigin),
            topOrigin: SumiPermissionOrigin(string: topOrigin ?? requestingOrigin),
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

private func XCTAssertThrowsErrorAsync(
    _ expression: () async throws -> Void,
    file: StaticString = #filePath,
    line: UInt = #line
) async {
    do {
        try await expression()
        XCTFail("Expected error to be thrown", file: file, line: line)
    } catch {
        return
    }
}
