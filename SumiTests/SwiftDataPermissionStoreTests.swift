import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SwiftDataPermissionStoreTests: XCTestCase {
    func testInsertAllowDenyAndAskDecisions() async throws {
        let harness = try makeHarness()
        try await harness.store.setDecision(
            for: key(.camera),
            decision: decision(.allow)
        )
        try await harness.store.setDecision(
            for: key(.microphone),
            decision: decision(.deny)
        )
        try await harness.store.setDecision(
            for: key(.geolocation),
            decision: decision(.ask)
        )

        let records = try await harness.store.listDecisions(profilePartitionId: "profile-a")
        XCTAssertEqual(Set(records.map(\.decision.state)), [.allow, .deny, .ask])
        XCTAssertEqual(records.count, 3)
    }

    func testUpdateDecision() async throws {
        let harness = try makeHarness()
        let permissionKey = key(.camera)
        try await harness.store.setDecision(
            for: permissionKey,
            decision: decision(.allow, updatedAt: date("2026-04-28T10:00:00Z"))
        )
        try await harness.store.setDecision(
            for: permissionKey,
            decision: decision(.deny, updatedAt: date("2026-04-28T11:00:00Z"))
        )

        let fetchedRecord = try await harness.store.getDecision(for: permissionKey)
        let record = try XCTUnwrap(fetchedRecord)
        XCTAssertEqual(record.decision.state, .deny)
        XCTAssertEqual(record.decision.updatedAt, date("2026-04-28T11:00:00Z"))
        let records = try await harness.store.listDecisions(profilePartitionId: "profile-a")
        XCTAssertEqual(records.count, 1)
    }

    func testResetDecision() async throws {
        let harness = try makeHarness()
        let permissionKey = key(.camera)
        try await harness.store.setDecision(for: permissionKey, decision: decision(.allow))

        try await harness.store.resetDecision(for: permissionKey)

        let record = try await harness.store.getDecision(for: permissionKey)
        XCTAssertNil(record)
    }

    func testListByProfile() async throws {
        let harness = try makeHarness()
        try await harness.store.setDecision(
            for: key(.camera, profile: "profile-a"),
            decision: decision(.allow)
        )
        try await harness.store.setDecision(
            for: key(.camera, profile: "profile-b"),
            decision: decision(.deny)
        )

        let records = try await harness.store.listDecisions(profilePartitionId: "PROFILE-A")

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.key.profilePartitionId, "profile-a")
    }

    func testListByDisplayDomain() async throws {
        let harness = try makeHarness()
        try await harness.store.setDecision(
            for: key(.camera, requesting: "https://camera.example"),
            decision: decision(.allow)
        )
        try await harness.store.setDecision(
            for: key(.microphone, requesting: "https://other.example"),
            decision: decision(.allow)
        )

        let records = try await harness.store.listDecisions(
            forDisplayDomain: "Camera.Example",
            profilePartitionId: "profile-a"
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(records.first?.displayDomain, "camera.example")
    }

    func testExplicitAskRoundTrip() async throws {
        let harness = try makeHarness()
        let permissionKey = key(.notifications)
        try await harness.store.setDecision(
            for: permissionKey,
            decision: decision(.ask, reason: "reset-to-ask")
        )

        let fetchedRecord = try await harness.store.getDecision(for: permissionKey)
        let record = try XCTUnwrap(fetchedRecord)
        XCTAssertEqual(record.decision.state, .ask)
        XCTAssertEqual(record.decision.reason, "reset-to-ask")
    }

    func testNoPersistentWriteForEphemeralProfile() async throws {
        let harness = try makeHarness()
        let permissionKey = key(.camera, isEphemeral: true)

        do {
            try await harness.store.setDecision(
                for: permissionKey,
                decision: decision(.allow)
            )
            XCTFail("Expected persistent writes for ephemeral profiles to fail")
        } catch let error as SumiPermissionStoreError {
            XCTAssertEqual(error, .persistentWriteForEphemeralProfile)
        }
    }

    private func makeHarness() throws -> (
        container: ModelContainer,
        store: SwiftDataPermissionStore
    ) {
        let container = try ModelContainer(
            for: Schema([PermissionDecisionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        return (container, SwiftDataPermissionStore(container: container))
    }

    private func key(
        _ type: SumiPermissionType,
        requesting: String = "https://example.com",
        top: String = "https://example.com",
        profile: String = "profile-a",
        isEphemeral: Bool = false
    ) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: requesting),
            topOrigin: SumiPermissionOrigin(string: top),
            permissionType: type,
            profilePartitionId: profile,
            isEphemeralProfile: isEphemeral
        )
    }

    private func decision(
        _ state: SumiPermissionState,
        reason: String? = nil,
        updatedAt: Date? = nil
    ) -> SumiPermissionDecision {
        let now = updatedAt ?? date("2026-04-28T10:00:00Z")
        return SumiPermissionDecision(
            state: state,
            persistence: .persistent,
            source: .user,
            reason: reason,
            createdAt: date("2026-04-28T09:00:00Z"),
            updatedAt: now,
            metadata: ["test": "value"]
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
