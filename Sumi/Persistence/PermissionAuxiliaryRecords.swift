import Foundation
import GRDB
import SumiDomain

struct PermissionAuxiliaryState {
    var generation: UInt64
    var antiAbuseEvents: [SumiPermissionAntiAbuseEvent]
    var siteActivityRecords: [SumiPermissionSiteActivityRecord]
}

private struct PermissionAuxiliaryStateRow:
    Codable,
    FetchableRecord,
    PersistableRecord
{
    static let databaseTableName = "permission_state"

    let id: Int
    var generation: Int64
    var antiAbuseEvents: Data
    var siteActivityRecords: Data

    private enum CodingKeys: String, CodingKey {
        case id, generation
        case antiAbuseEvents = "anti_abuse_events"
        case siteActivityRecords = "site_activity_records"
    }
}

struct PermissionAuxiliaryRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func load() throws -> PermissionAuxiliaryState {
        guard let row = try PermissionAuxiliaryStateRow.fetchOne(
            database,
            key: 1
        ) else {
            return .init(
                generation: 0,
                antiAbuseEvents: [],
                siteActivityRecords: []
            )
        }
        return PermissionAuxiliaryState(
            generation: UInt64(max(0, row.generation)),
            antiAbuseEvents: try JSONDecoder().decode(
                [SumiPermissionAntiAbuseEvent].self,
                from: row.antiAbuseEvents
            ),
            siteActivityRecords: try JSONDecoder().decode(
                [SumiPermissionSiteActivityRecord].self,
                from: row.siteActivityRecords
            )
        )
    }

    func save(_ state: PermissionAuxiliaryState) throws {
        try PermissionAuxiliaryStateRow(
            id: 1,
            generation: Int64(state.generation),
            antiAbuseEvents: JSONEncoder().encode(state.antiAbuseEvents),
            siteActivityRecords: JSONEncoder().encode(
                state.siteActivityRecords
            )
        ).save(database)
    }
}
