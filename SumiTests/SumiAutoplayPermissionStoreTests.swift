import SwiftData
import XCTest

@testable import Sumi
import SumiDomain

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
        XCTAssertNotNil(harness.adapter.explicitPolicy(for: url, profile: profile))

        try await harness.adapter.resetPolicy(for: url, profile: profile)

        let key = try XCTUnwrap(harness.adapter.key(for: url, profile: profile))
        let storedRecord = try await harness.store.getDecision(for: key)
        XCTAssertNil(storedRecord)
        XCTAssertNil(harness.adapter.explicitPolicy(for: url, profile: profile))
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

    func testInjectedStoreIsUsedForPersistentAutoplayFetches() async throws {
        let firstHarness = try makeHarness()
        let secondHarness = try makeHarness()
        let profile = makeProfile("99999999-9999-9999-9999-999999999999")
        let url = URL(string: "https://example.com/video")!

        try await firstHarness.adapter.setPolicy(.blockAll, for: url, profile: profile)

        XCTAssertEqual(firstHarness.adapter.effectivePolicy(for: url, profile: profile), .blockAll)
        XCTAssertEqual(secondHarness.adapter.effectivePolicy(for: url, profile: profile), .default)
    }

    func testAdapterDoesNotOpenModelContextForSyncReads() async throws {
        let harness = try makeHarness()
        let profile = makeProfile("aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")
        let url = URL(string: "https://example.com/video")!

        try await harness.adapter.setPolicy(.blockAudible, for: url, profile: profile)

        // Sync path must hit the in-memory cache seeded by setPolicy, not a ModelContext fetch.
        XCTAssertEqual(harness.adapter.effectivePolicy(for: url, profile: profile), .blockAudible)
        XCTAssertTrue(
            String(describing: type(of: harness.adapter.permissionStore))
                .contains("SwiftDataPermissionStore")
        )
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

        XCTAssertNil(harness.adapter.explicitPolicy(for: url, profile: profile))
        XCTAssertEqual(harness.adapter.effectivePolicy(for: url, profile: profile), .default)
    }

    func testProfileSealDrainsAdmittedWriteAndRejectsLateRecreation() async throws {
        let store = SuspendingAutoplayPermissionStore()
        let admission = SumiPermissionProfileAdmission()
        let adapter = SumiAutoplayPolicyStoreAdapter(
            persistentStore: store,
            profileAdmission: admission
        )
        let targetKey = autoplayKey(
            profileID: "target-profile",
            host: "target.example"
        )
        let retainedKey = autoplayKey(
            profileID: "retained-profile",
            host: "retained.example"
        )
        let admittedWrite = Task { @MainActor in
            try await adapter.setPolicy(.blockAll, for: targetKey)
        }
        await store.waitUntilWriteIsSuspended()

        let profileID = await adapter.sealProfile("target-profile")
        let drainCompletion = AutoplayRetirementCompletionProbe()
        let drain = Task { @MainActor in
            await adapter.waitForProfileDrain(profileID)
            await drainCompletion.markCompleted()
        }
        for _ in 0..<20 {
            await Task.yield()
        }
        let completedBeforeWriteDrain = await drainCompletion.isCompleted()
        XCTAssertFalse(completedBeforeWriteDrain)

        await store.resumeWrite()
        try await admittedWrite.value
        await drain.value
        await store.resetDecision(for: targetKey)

        do {
            try await adapter.setPolicy(.allowAll, for: targetKey)
            XCTFail("Retired autoplay profile accepted a late write")
        } catch SumiPermissionSiteDecisionError.unavailable {
            // Expected fail-closed behavior.
        }
        try await adapter.setPolicy(.allowAll, for: retainedKey)

        let targetRecords = await store.listDecisions(
            profilePartitionId: "target-profile"
        )
        let retainedRecords = await store.listDecisions(
            profilePartitionId: "retained-profile"
        )
        XCTAssertTrue(targetRecords.isEmpty)
        XCTAssertEqual(retainedRecords.count, 1)
        XCTAssertNil(adapter.explicitPolicy(for: targetKey))
        XCTAssertEqual(adapter.explicitPolicy(for: retainedKey), .allowAll)
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
        let adapter = SumiAutoplayPolicyStoreAdapter(persistentStore: store)
        return (container, store, adapter)
    }

    private func makeProfile(_ id: String) -> Profile {
        Profile(id: UUID(uuidString: id)!, name: "Profile", icon: "person")
    }

    private func autoplayKey(
        profileID: String,
        host: String
    ) -> SumiPermissionKey {
        let origin = SumiPermissionOrigin(string: "https://\(host)")
        return SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .autoplay,
            profilePartitionId: profileID
        )
    }
}

private actor AutoplayRetirementCompletionProbe {
    private var completed = false

    func markCompleted() {
        completed = true
    }

    func isCompleted() -> Bool {
        completed
    }
}

private actor SuspendingAutoplayPermissionStore: SumiPermissionStore {
    private var records: [String: SumiPermissionStoreRecord] = [:]
    private var suspendedWrite: CheckedContinuation<Void, Never>?
    private var shouldSuspendNextWrite = true

    func getDecision(for key: SumiPermissionKey) async -> SumiPermissionStoreRecord? {
        records[key.persistentIdentity]
    }

    func setDecision(
        for key: SumiPermissionKey,
        decision: SumiPermissionDecision
    ) async {
        if shouldSuspendNextWrite {
            shouldSuspendNextWrite = false
            await withCheckedContinuation { continuation in
                suspendedWrite = continuation
            }
        }
        records[key.persistentIdentity] = SumiPermissionStoreRecord(
            key: key,
            decision: decision
        )
    }

    func resetDecision(for key: SumiPermissionKey) async {
        records.removeValue(forKey: key.persistentIdentity)
    }

    func listDecisions(
        profilePartitionId: String
    ) async -> [SumiPermissionStoreRecord] {
        let profileID = SumiPermissionKey.normalizedProfilePartitionId(
            profilePartitionId
        )
        return records.values.filter {
            $0.key.profilePartitionId == profileID
        }
    }

    func recordLastUsed(for _: SumiPermissionKey, at _: Date) async {}

    func waitUntilWriteIsSuspended() async {
        while suspendedWrite == nil {
            await Task.yield()
        }
    }

    func resumeWrite() {
        suspendedWrite?.resume()
        suspendedWrite = nil
    }
}
