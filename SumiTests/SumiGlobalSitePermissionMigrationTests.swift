import Foundation
import GRDB
import XCTest

@testable import Sumi
import SumiDomain

@MainActor
final class SumiGlobalSitePermissionMigrationTests: XCTestCase {
    func testVersionFourDecisionsCollapseIntoOneGlobalDeny() async throws {
        let rootURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("SumiGlobalSitePermissionMigration-\(UUID().uuidString)")
        let databaseURL = rootURL.appendingPathComponent("Sumi.sqlite")
        try FileManager.default.createDirectory(at: rootURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: rootURL) }

        let firstProfile = UUID(uuidString: "11111111-1111-4111-8111-111111111111")!
        let secondProfile = UUID(uuidString: "22222222-2222-4222-8222-222222222222")!
        let allowRecord = record(
            profileID: firstProfile,
            state: .allow,
            updatedAt: Date(timeIntervalSince1970: 10)
        )
        let denyRecord = record(
            profileID: secondProfile,
            state: .deny,
            updatedAt: Date(timeIntervalSince1970: 20)
        )
        do {
            let queue = try DatabaseQueue(path: databaseURL.path)
            try await queue.write { database in
                try database.execute(sql: """
                    CREATE TABLE permission_decisions (
                        identity TEXT PRIMARY KEY,
                        profile_id BLOB NOT NULL,
                        profile_partition_id TEXT NOT NULL,
                        requesting_origin TEXT NOT NULL,
                        top_origin TEXT NOT NULL,
                        permission_type TEXT NOT NULL,
                        display_domain TEXT NOT NULL,
                        state TEXT NOT NULL,
                        persistence TEXT NOT NULL,
                        source TEXT NOT NULL,
                        reason TEXT,
                        created_at DATETIME NOT NULL,
                        updated_at DATETIME NOT NULL,
                        expires_at DATETIME,
                        last_used_at DATETIME,
                        system_authorization TEXT,
                        metadata BLOB
                    )
                    """)
                try PermissionDecisionRow(record: allowRecord).insert(database)
                try PermissionDecisionRow(record: denyRecord).insert(database)
                try database.execute(sql: "PRAGMA user_version = 4")
            }
        }

        let database = try SumiDatabase.open(at: databaseURL)
        let rawStore = DatabasePermissionStore(database: database)
        let globalRecords = try await rawStore.listDecisions(
            profilePartitionId: SumiGlobalSitePermissionScope.profilePartitionId
        )

        XCTAssertEqual(globalRecords.count, 1)
        XCTAssertEqual(globalRecords.first?.decision.state, .deny)
        XCTAssertEqual(
            globalRecords.first?.key.profilePartitionId,
            SumiGlobalSitePermissionScope.profilePartitionId
        )
        let oldProfileRecords = try database.read {
            try $0.permissions.all(profilePartitionID: firstProfile.uuidString)
        }
        XCTAssertTrue(oldProfileRecords.isEmpty)

        let resolvedRecord = try await rawStore.getDecision(for: key(profileID: firstProfile))
        let resolved = try XCTUnwrap(resolvedRecord)
        XCTAssertEqual(resolved.key.profilePartitionId, firstProfile.uuidString.lowercased())
        XCTAssertEqual(resolved.decision.state, .deny)
    }

    private func record(
        profileID: UUID,
        state: SumiPermissionState,
        updatedAt: Date
    ) -> SumiPermissionStoreRecord {
        SumiPermissionStoreRecord(
            key: key(profileID: profileID),
            decision: SumiPermissionDecision(
                state: state,
                persistence: .persistent,
                source: .user,
                createdAt: Date(timeIntervalSince1970: 1),
                updatedAt: updatedAt
            )
        )
    }

    private func key(profileID: UUID) -> SumiPermissionKey {
        let origin = SumiPermissionOrigin(string: "https://camera.example")
        return SumiPermissionKey(
            requestingOrigin: origin,
            topOrigin: origin,
            permissionType: .camera,
            profilePartitionId: profileID.uuidString
        )
    }
}
