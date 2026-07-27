import Foundation
import GRDB

struct ProfileRetirementRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "profile_retirements"

    let profileID: UUID
    var profileName: String
    var profileIndex: Int
    var fallbackProfileID: UUID
    let generation: UUID
    var phaseRawValue: String
    var nextCleanupStepRawValue: String

    private enum CodingKeys: String, CodingKey {
        case profileID = "profile_id"
        case profileName = "profile_name"
        case profileIndex = "profile_position"
        case fallbackProfileID = "fallback_profile_id"
        case generation
        case phaseRawValue = "phase"
        case nextCleanupStepRawValue = "next_cleanup_step"
    }
}

struct ProfileRetirementRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func all() throws -> [ProfileRetirementRow] {
        try ProfileRetirementRow
            .order(Column("profile_position"))
            .fetchAll(database)
    }

    func find(profileID: UUID) throws -> ProfileRetirementRow? {
        try ProfileRetirementRow.fetchOne(database, key: profileID)
    }

    func save(_ row: ProfileRetirementRow) throws {
        try row.save(database)
    }

    func delete(profileID: UUID) throws {
        _ = try ProfileRetirementRow.deleteOne(database, key: profileID)
    }
}
