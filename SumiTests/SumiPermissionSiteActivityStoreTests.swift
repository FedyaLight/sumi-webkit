import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class SumiPermissionSiteActivityStoreTests: XCTestCase {
    func testPersistentActivityReloadsFromBrowserDatabase() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiPermissionActivity-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let databaseURL = directory.appendingPathComponent("Sumi.sqlite")
        let key = makeKey(.camera, profile: "profile-a")
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        let firstAuthority = SumiPermissionPersistenceAuthority(
            database: try SumiDatabase.open(at: databaseURL)
        )
        let firstStore = SumiPermissionSiteActivityStore(
            persistenceAuthority: firstAuthority
        )
        firstStore.recordSettingsChange(
            displayDomain: "example.com",
            key: key,
            state: .allow,
            reason: "settings",
            now: now
        )
        let didFlush = await firstAuthority.flushPendingWrites()
        XCTAssertTrue(didFlush)

        let secondStore = SumiPermissionSiteActivityStore(
            persistenceAuthority: SumiPermissionPersistenceAuthority(
                database: try SumiDatabase.open(at: databaseURL)
            )
        )
        let record = try XCTUnwrap(
            secondStore.records(
                forSiteOf: key.topOrigin,
                profilePartitionId: key.profilePartitionId,
                isEphemeralProfile: false
            ).first
        )
        XCTAssertEqual(record.lastState, .allow)
        XCTAssertEqual(record.reason, "settings")
    }

    func testRetiredProfileCannotRecreateActivity() async throws {
        let authority = SumiPermissionPersistenceAuthority(
            database: try SumiDatabase.inMemory()
        )
        let store = SumiPermissionSiteActivityStore(
            persistenceAuthority: authority
        )
        let retired = makeKey(.camera, profile: "retired")
        let retained = makeKey(.camera, profile: "retained")
        for key in [retired, retained] {
            store.recordSettingsChange(
                displayDomain: key.displayDomain,
                key: key,
                state: .allow,
                reason: "before"
            )
        }

        store.retireProfile("retired")
        try await authority.deleteProfileData(profilePartitionId: "retired")
        store.recordSettingsChange(
            displayDomain: retired.displayDomain,
            key: retired,
            state: .deny,
            reason: "late"
        )

        XCTAssertTrue(
            store.records(
                forSiteOf: retired.topOrigin,
                profilePartitionId: "retired",
                isEphemeralProfile: false
            ).isEmpty
        )
        XCTAssertEqual(
            store.records(
                forSiteOf: retained.topOrigin,
                profilePartitionId: "retained",
                isEphemeralProfile: false
            ).first?.lastState,
            .allow
        )
    }

    private func makeKey(
        _ type: SumiPermissionType,
        profile: String
    ) -> SumiPermissionKey {
        SumiPermissionKey(
            requestingOrigin: SumiPermissionOrigin(string: "https://example.com/path"),
            topOrigin: SumiPermissionOrigin(string: "https://example.com"),
            permissionType: type,
            profilePartitionId: profile,
            isEphemeralProfile: false
        )
    }
}
