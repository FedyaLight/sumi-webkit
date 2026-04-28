import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class SumiAutoplayPermissionStoreTests: XCTestCase {
    func testSetAllowStoresCanonicalAutoplayDecision() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")
        let url = URL(string: "https://example.com/video")!

        try await harness.adapter.setPolicy(.allowAll, for: url, profile: profile)

        let key = try XCTUnwrap(harness.adapter.key(for: url, profile: profile))
        let storedRecord = try await harness.store.getDecision(for: key)
        let record = try XCTUnwrap(storedRecord)
        XCTAssertEqual(record.key.permissionType, .autoplay)
        XCTAssertEqual(record.key.requestingOrigin, SumiPermissionOrigin(string: "https://example.com"))
        XCTAssertEqual(record.key.topOrigin, SumiPermissionOrigin(string: "https://example.com"))
        XCTAssertEqual(record.key.profilePartitionId, profile.id.uuidString.lowercased())
        XCTAssertEqual(record.decision.state, .allow)
        XCTAssertEqual(record.decision.source, .user)
        XCTAssertEqual(record.decision.metadata?[SumiAutoplayDecisionMapper.metadataKey], "allowAll")
    }

    func testSetBlockAudibleStoresCanonicalDenyWithMetadata() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")
        let url = URL(string: "https://media.example/path")!

        try await harness.adapter.setPolicy(.blockAudible, for: url, profile: profile)

        let key = try XCTUnwrap(harness.adapter.key(for: url, profile: profile))
        let storedRecord = try await harness.store.getDecision(for: key)
        let record = try XCTUnwrap(storedRecord)
        XCTAssertEqual(record.decision.state, .deny)
        XCTAssertEqual(record.decision.metadata?[SumiAutoplayDecisionMapper.metadataKey], "blockAudible")
        XCTAssertEqual(harness.adapter.effectivePolicy(for: url, profile: profile), .blockAudible)
    }

    func testSetBlockAllStoresCanonicalDenyWithMetadata() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("cccccccc-cccc-cccc-cccc-cccccccccccc")
        let url = URL(string: "https://media.example/path")!

        try await harness.adapter.setPolicy(.blockAll, for: url, profile: profile)

        let key = try XCTUnwrap(harness.adapter.key(for: url, profile: profile))
        let storedRecord = try await harness.store.getDecision(for: key)
        let record = try XCTUnwrap(storedRecord)
        XCTAssertEqual(record.decision.state, .deny)
        XCTAssertEqual(record.decision.metadata?[SumiAutoplayDecisionMapper.metadataKey], "blockAll")
        XCTAssertEqual(harness.adapter.effectivePolicy(for: url, profile: profile), .blockAll)
    }

    func testResetRemovesCanonicalDecision() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("dddddddd-dddd-dddd-dddd-dddddddddddd")
        let url = URL(string: "https://example.com/video")!

        try await harness.adapter.setPolicy(.blockAll, for: url, profile: profile)
        XCTAssertTrue(harness.adapter.hasExplicitPolicy(for: url, profile: profile))

        try await harness.adapter.resetPolicy(for: url, profile: profile)

        let key = try XCTUnwrap(harness.adapter.key(for: url, profile: profile))
        let storedRecord = try await harness.store.getDecision(for: key)
        XCTAssertNil(storedRecord)
        XCTAssertFalse(harness.adapter.hasExplicitPolicy(for: url, profile: profile))
        XCTAssertEqual(harness.adapter.effectivePolicy(for: url, profile: profile), .default)
    }

    func testDecisionsAreProfilePartitioned() async throws {
        let harness = try makeHarness()
        let profileA = makeProfile("eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee")
        let profileB = makeProfile("ffffffff-ffff-ffff-ffff-ffffffffffff")
        let url = URL(string: "https://example.com/video")!

        try await harness.adapter.setPolicy(.blockAll, for: url, profile: profileA)

        XCTAssertEqual(harness.adapter.effectivePolicy(for: url, profile: profileA), .blockAll)
        XCTAssertEqual(harness.adapter.effectivePolicy(for: url, profile: profileB), .default)
    }

    func testPersistentIdentityIncludesTopOrigin() {
        let requesting = SumiPermissionOrigin(string: "https://cdn.example")
        let firstTop = SumiPermissionOrigin(string: "https://first.example")
        let secondTop = SumiPermissionOrigin(string: "https://second.example")

        let first = SumiPermissionKey(
            requestingOrigin: requesting,
            topOrigin: firstTop,
            permissionType: .autoplay,
            profilePartitionId: "profile-a"
        )
        let second = SumiPermissionKey(
            requestingOrigin: requesting,
            topOrigin: secondTop,
            permissionType: .autoplay,
            profilePartitionId: "profile-a"
        )

        XCTAssertNotEqual(first.persistentIdentity, second.persistentIdentity)
    }

    func testEphemeralProfileDoesNotPersistDecision() async throws {
        let harness = try makeHarness()
        let profile = Profile.createEphemeral()
        let url = URL(string: "https://private.example/video")!

        try await harness.adapter.setPolicy(.blockAll, for: url, profile: profile)

        XCTAssertEqual(harness.adapter.effectivePolicy(for: url, profile: profile), .blockAll)
        let records = try await harness.store.listDecisions(
            profilePartitionId: profile.id.uuidString
        )
        XCTAssertTrue(records.isEmpty)

        try await harness.adapter.resetPolicy(for: url, profile: profile)
        XCTAssertEqual(harness.adapter.effectivePolicy(for: url, profile: profile), .default)
    }

    func testOldUserDefaultsAutoplayValueIsIgnored() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("11111111-2222-3333-4444-555555555555")
        let url = URL(string: "https://legacy.example/video")!
        UserDefaults.standard.set(
            Data(#"{"11111111-2222-3333-4444-555555555555":{"legacy.example":"block"}}"#.utf8),
            forKey: "settings.sitePermissionOverrides.autoplay"
        )
        defer {
            UserDefaults.standard.removeObject(forKey: "settings.sitePermissionOverrides.autoplay")
        }

        XCTAssertFalse(harness.adapter.hasExplicitPolicy(for: url, profile: profile))
        XCTAssertEqual(harness.adapter.effectivePolicy(for: url, profile: profile), .default)
    }

    private func makeHarness() throws -> (
        container: ModelContainer,
        store: SwiftDataPermissionStore,
        adapter: SumiAutoplayPolicyStoreAdapter
    ) {
        let container = try ModelContainer(
            for: Schema([PermissionDecisionEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = SwiftDataPermissionStore(container: container)
        let adapter = SumiAutoplayPolicyStoreAdapter(
            modelContainer: container,
            persistentStore: store
        )
        return (container, store, adapter)
    }

    private func makeProfile(_ id: String) -> Profile {
        Profile(id: UUID(uuidString: id)!, name: "Profile", icon: "person")
    }
}
