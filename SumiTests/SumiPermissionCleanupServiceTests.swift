import XCTest

@testable import Sumi
import SumiDomain

private let permissionCleanupServiceFixedDate = Date(timeIntervalSince1970: 1_800_000_300)

@MainActor
final class SumiPermissionCleanupServiceTests: XCTestCase {
    func testStoreFailureReturnsFailedInsteadOfCompleted() async {
        let profile = Profile(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            name: "Profile",
            icon: "person"
        )
        let service = SumiPermissionCleanupService(
            store: FailingCleanupPermissionStore(),
            recentActivityStore: SumiPermissionRecentActivityStore(),
            userDefaults: UserDefaults(suiteName: "SumiPermissionCleanupServiceTests")!,
            now: { permissionCleanupServiceFixedDate }
        )

        let result = await service.run(
            profile: SumiPermissionSettingsProfileContext(profile: profile),
            settings: SumiPermissionCleanupSettings(isAutomaticCleanupEnabled: true),
            force: true
        )

        guard case .failed(let errorDescription) = result else {
            return XCTFail("Expected cleanup failure, got \(result)")
        }
        XCTAssertTrue(errorDescription.contains("listFailed"))
    }

    func testProfileRetirementDeletesEveryPermissionDomainAndRetainsOtherProfile() async throws {
        let targetProfileID = "target-profile"
        let retainedProfileID = "retained-profile"
        let defaultsSuite = "SumiPermissionCleanupProfileTests-\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsSuite))
        defer { defaults.removePersistentDomain(forName: defaultsSuite) }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiPermissionCleanupProfileTests-\(UUID().uuidString)",
            isDirectory: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }

        let permissionStore = InMemoryPermissionCleanupStore()
        let targetKey = makePermissionKey(profileID: targetProfileID, host: "target.example")
        let retainedKey = makePermissionKey(profileID: retainedProfileID, host: "retained.example")
        let decision = SumiPermissionDecision(
            state: .allow,
            persistence: .persistent,
            source: .user
        )
        try await permissionStore.setDecision(for: targetKey, decision: decision)
        try await permissionStore.setDecision(for: retainedKey, decision: decision)

        let recentStore = SumiPermissionRecentActivityStore()
        recentStore.recordSettingsChange(
            displayDomain: "target.example",
            key: targetKey,
            state: .allow
        )
        recentStore.recordSettingsChange(
            displayDomain: "retained.example",
            key: retainedKey,
            state: .allow
        )

        let authority = SumiPermissionPersistenceAuthority(
            userDefaults: defaults,
            storageDirectory: directory
        )
        let siteActivityStore = SumiPermissionSiteActivityStore(
            persistenceAuthority: authority
        )
        let antiAbuseStore = SumiPermissionAntiAbuseStore(
            persistenceAuthority: authority
        )
        siteActivityStore.recordSettingsChange(
            displayDomain: "target.example",
            key: targetKey,
            state: .allow,
            reason: "test"
        )
        siteActivityStore.recordSettingsChange(
            displayDomain: "retained.example",
            key: retainedKey,
            state: .allow,
            reason: "test"
        )
        await antiAbuseStore.record(
            SumiPermissionAntiAbuseEvent(type: .promptShown, key: targetKey)
        )
        await antiAbuseStore.record(
            SumiPermissionAntiAbuseEvent(type: .promptShown, key: retainedKey)
        )
        defaults.set(Date(), forKey: "permissions.cleanup.last-run.v1.\(targetProfileID)")
        defaults.set(1, forKey: "permissions.cleanup.last-removed-count.v1.\(targetProfileID)")
        defaults.set(Date(), forKey: "permissions.cleanup.last-run.v1.\(retainedProfileID)")

        let service = SumiPermissionCleanupService(
            store: permissionStore,
            recentActivityStore: recentStore,
            antiAbuseStore: antiAbuseStore,
            siteActivityStore: siteActivityStore,
            userDefaults: defaults
        )
        try await service.deleteAllDecisions(
            profilePartitionId: targetProfileID
        )
        try await service.deleteAllDecisions(
            profilePartitionId: targetProfileID
        )

        let targetDecisions = try await permissionStore.listDecisions(
            profilePartitionId: targetProfileID
        )
        let retainedDecisions = try await permissionStore.listDecisions(
            profilePartitionId: retainedProfileID
        )
        let targetAntiAbuseEvents = await antiAbuseStore.events(
            for: targetKey,
            now: Date()
        )
        let retainedAntiAbuseEvents = await antiAbuseStore.events(
            for: retainedKey,
            now: Date()
        )
        XCTAssertTrue(targetDecisions.isEmpty)
        XCTAssertEqual(retainedDecisions.count, 1)
        XCTAssertTrue(
            recentStore.records(
                profilePartitionId: targetProfileID,
                isEphemeralProfile: false
            ).isEmpty
        )
        XCTAssertEqual(
            recentStore.records(
                profilePartitionId: retainedProfileID,
                isEphemeralProfile: false
            ).count,
            1
        )
        XCTAssertTrue(targetAntiAbuseEvents.isEmpty)
        XCTAssertEqual(retainedAntiAbuseEvents.count, 1)
        XCTAssertTrue(
            siteActivityStore.records(
                forSiteOf: targetKey.topOrigin,
                profilePartitionId: targetProfileID,
                isEphemeralProfile: false
            ).isEmpty
        )
        XCTAssertEqual(
            siteActivityStore.records(
                forSiteOf: retainedKey.topOrigin,
                profilePartitionId: retainedProfileID,
                isEphemeralProfile: false
            ).count,
            1
        )
        XCTAssertNil(
            defaults.object(
                forKey: "permissions.cleanup.last-run.v1.\(targetProfileID)"
            )
        )
        XCTAssertNil(
            defaults.object(
                forKey: "permissions.cleanup.last-removed-count.v1.\(targetProfileID)"
            )
        )
        XCTAssertNotNil(
            defaults.object(
                forKey: "permissions.cleanup.last-run.v1.\(retainedProfileID)"
            )
        )
    }

    func testCorruptCanonicalPermissionStateBlocksProfileCleanup() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(
            "SumiPermissionCleanupCorruptTests-\(UUID().uuidString)",
            isDirectory: true
        )
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer { try? FileManager.default.removeItem(at: directory) }
        let canonicalURL = directory.appendingPathComponent(
            SumiPermissionPersistenceAuthority.canonicalFileName
        )
        let corruptData = Data("not-json".utf8)
        try corruptData.write(to: canonicalURL)
        let siteActivityStore = SumiPermissionSiteActivityStore(
            persistenceAuthority: SumiPermissionPersistenceAuthority(
                userDefaults: nil,
                storageDirectory: directory
            )
        )
        let service = SumiPermissionCleanupService(
            store: InMemoryPermissionCleanupStore(),
            recentActivityStore: SumiPermissionRecentActivityStore(),
            siteActivityStore: siteActivityStore
        )

        do {
            try await service.deleteAllDecisions(profilePartitionId: "target")
            XCTFail("Expected corrupt canonical state to fail closed")
        } catch SumiPermissionProfileDataCleanupError.persistenceStateUnreadable {
            // Expected.
        }

        XCTAssertEqual(try Data(contentsOf: canonicalURL), corruptData)
    }

    private func makePermissionKey(
        profileID: String,
        host: String
    ) -> SumiPermissionKey {
        let origin = SumiPermissionOrigin(string: "https://\(host)")
        return SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .camera,
            profilePartitionId: profileID
        )
    }
}

private enum FailingCleanupPermissionStoreError: Error {
    case listFailed
}

private actor FailingCleanupPermissionStore: SumiPermissionStore {
    func getDecision(for _: SumiPermissionKey) async -> SumiPermissionStoreRecord? {
        nil
    }

    func setDecision(for _: SumiPermissionKey, decision _: SumiPermissionDecision) async { /* No-op. */ }

    func resetDecision(for _: SumiPermissionKey) async { /* No-op. */ }

    func listDecisions(profilePartitionId _: String) async throws -> [SumiPermissionStoreRecord] {
        throw FailingCleanupPermissionStoreError.listFailed
    }

    func recordLastUsed(for _: SumiPermissionKey, at _: Date) async { /* No-op. */ }
}

private actor InMemoryPermissionCleanupStore: SumiPermissionStore {
    private var records: [SumiPermissionKey: SumiPermissionStoreRecord] = [:]

    func getDecision(
        for key: SumiPermissionKey
    ) async throws -> SumiPermissionStoreRecord? {
        records[key]
    }

    func setDecision(
        for key: SumiPermissionKey,
        decision: SumiPermissionDecision
    ) async throws {
        records[key] = SumiPermissionStoreRecord(key: key, decision: decision)
    }

    func resetDecision(for key: SumiPermissionKey) async throws {
        records.removeValue(forKey: key)
    }

    func listDecisions(
        profilePartitionId: String
    ) async throws -> [SumiPermissionStoreRecord] {
        records.values.filter {
            $0.key.profilePartitionId == profilePartitionId
        }
    }

    func recordLastUsed(for _: SumiPermissionKey, at _: Date) async throws {}
}
