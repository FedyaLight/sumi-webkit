import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class DatabasePermissionStoreTests: XCTestCase {
    private let profileA = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
    private let profileB = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!

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

        let records = try await harness.store.listDecisions(
            profilePartitionId: profileA.uuidString
        )
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
        let records = try await harness.store.listDecisions(
            profilePartitionId: profileA.uuidString
        )
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
            for: key(.camera, profile: profileA.uuidString),
            decision: decision(.allow)
        )
        try await harness.store.setDecision(
            for: key(.camera, profile: profileB.uuidString),
            decision: decision(.deny)
        )

        let records = try await harness.store.listDecisions(
            profilePartitionId: profileA.uuidString.uppercased()
        )

        XCTAssertEqual(records.count, 1)
        XCTAssertEqual(
            records.first?.key.profilePartitionId,
            profileA.uuidString.lowercased()
        )
    }

    func testListRecordsCanBeFilteredByDisplayDomain() async throws {
        let harness = try makeHarness()
        try await harness.store.setDecision(
            for: key(.camera, requesting: "https://camera.example"),
            decision: decision(.allow)
        )
        try await harness.store.setDecision(
            for: key(.microphone, requesting: "https://other.example"),
            decision: decision(.allow)
        )

        let records = try await harness.store
            .listDecisions(profilePartitionId: profileA.uuidString)
            .filter { $0.displayDomain == "camera.example" }

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

    func testPersistentWriteRequiresProfileUUID() async throws {
        let harness = try makeHarness()

        do {
            try await harness.store.setDecision(
                for: key(.camera, profile: "profile-a"),
                decision: decision(.allow)
            )
            XCTFail("Expected a non-UUID persistent profile partition to fail")
        } catch let error as SumiPermissionStoreError {
            XCTAssertEqual(
                error,
                .invalidPersistentProfilePartition("profile-a")
            )
        }
    }

    func testPersistentWriteRequiresExistingProfile() async throws {
        let harness = try makeHarness()
        let unknownProfileID = UUID()

        do {
            try await harness.store.setDecision(
                for: key(.camera, profile: unknownProfileID.uuidString),
                decision: decision(.allow)
            )
            XCTFail("Expected a foreign-key failure for an unknown profile")
        } catch {
            XCTAssertFalse(error is SumiPermissionStoreError)
        }
    }

    private func makeHarness() throws -> (
        container: SumiDatabase,
        store: DatabasePermissionStore
    ) {
        let container = try SumiDatabase.inMemory()
        try container.transaction {
            try $0.profiles.save(
                ProfileRecord(id: profileA, name: "Profile A", index: 0)
            )
            try $0.profiles.save(
                ProfileRecord(id: profileB, name: "Profile B", index: 1)
            )
        }
        return (container, DatabasePermissionStore(database: container))
    }

    private func key(
        _ type: SumiPermissionType,
        requesting: String = "https://example.com",
        top: String = "https://example.com",
        profile: String? = nil,
        isEphemeral: Bool = false
    ) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: requesting),
            topOrigin: SumiPermissionOrigin(string: top),
            permissionType: type,
            profilePartitionId: profile ?? profileA.uuidString,
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
