import XCTest

@testable import Sumi

@MainActor
final class ProfileRetirementDatabaseTests: XCTestCase {
    func testProfileManagerPublishesRemovalOnlyAfterLogicalCommit() throws {
        let browser = BrowserManager()
        let retiring = try XCTUnwrap(browser.currentProfile)
        let fallback = try browser.profileManager.createProfile(
            name: "Fallback"
        )
        let token = try browser.profileReferenceAdmission.reserve(
            profile: retiring,
            fallbackID: fallback.id
        )

        XCTAssertTrue(try browser.profileManager.beginReferenceMigration(token))
        XCTAssertTrue(
            browser.profileManager.profiles.contains {
                $0.id == retiring.id
            }
        )
        XCTAssertEqual(
            browser.profileManager.retiringProfileIDs,
            [retiring.id]
        )

        XCTAssertTrue(try browser.profileManager.commitLogicalDeletion(token))
        XCTAssertFalse(
            browser.profileManager.profiles.contains {
                $0.id == retiring.id
            }
        )
        XCTAssertTrue(browser.profileManager.retiringProfileIDs.isEmpty)
        XCTAssertEqual(browser.profileManager.profiles.map(\.id), [fallback.id])
    }

    func testRetirementJournalAndProfileDeletionShareDatabaseTransaction() throws {
        let database = try SumiDatabase.inMemory()
        let retiring = ProfileRecord(id: UUID(), name: "Retiring", index: 0)
        let fallback = ProfileRecord(id: UUID(), name: "Fallback", index: 1)
        let space = SpaceRecord(
            id: UUID(),
            profileID: retiring.id,
            name: "Space",
            icon: "🌐",
            index: 0,
            workspaceThemeData: nil
        )
        let fallbackSpace = SpaceRecord(
            id: UUID(),
            profileID: fallback.id,
            name: "Fallback Space",
            icon: "🌐",
            index: 1,
            workspaceThemeData: nil
        )
        try database.transaction {
            try $0.profiles.save(retiring)
            try $0.profiles.save(fallback)
            try $0.workspace.save(space)
            try $0.workspace.save(fallbackSpace)
        }

        let store = ProfileRetirementStore(database: database)
        let record = try store.reserve(
            profileID: retiring.id,
            fallbackProfileID: fallback.id,
            generation: UUID()
        )
        XCTAssertTrue(try store.beginReferenceMigration(record.token))
        XCTAssertTrue(try store.commitLogicalDeletion(record.token))

        let result = try database.read {
            (
                profiles: try $0.profiles.all(),
                spaces: try $0.workspace.spaces(),
                retirement: try $0.retirements.find(profileID: retiring.id)
            )
        }
        XCTAssertEqual(result.profiles.map(\.id), [fallback.id])
        XCTAssertEqual(result.profiles.first?.index, 0)
        XCTAssertEqual(result.spaces.map(\.id), [fallbackSpace.id])
        XCTAssertEqual(result.retirement?.phaseRawValue, ProfileRetirementPhase.logicallyDeleted.rawValue)
    }

    func testAdmissionLedgerBlocksReservedProfileAndAdmitsFallback() throws {
        let database = try SumiDatabase.inMemory()
        let retiring = ProfileRecord(id: UUID(), name: "Retiring", index: 0)
        let fallback = ProfileRecord(id: UUID(), name: "Fallback", index: 1)
        try database.transaction {
            try $0.profiles.save(retiring)
            try $0.profiles.save(fallback)
        }
        let store = ProfileRetirementStore(database: database)
        _ = try store.reserve(
            profileID: retiring.id,
            fallbackProfileID: fallback.id,
            generation: UUID()
        )

        let ledger = try ProfileReferenceAdmissionLedger(database: database)
        XCTAssertFalse(ledger.isReferenceAllowed(retiring.id))
        XCTAssertTrue(ledger.isReferenceAllowed(fallback.id))
    }
}
