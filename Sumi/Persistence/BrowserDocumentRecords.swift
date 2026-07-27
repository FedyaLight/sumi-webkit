import Foundation
import GRDB

private struct BrowserDocumentRow:
    Codable,
    FetchableRecord,
    PersistableRecord
{
    static let databaseTableName = "browser_documents"

    let key: String
    var payload: Data
    var updatedAt: Date

    private enum CodingKeys: String, CodingKey {
        case key, payload
        case updatedAt = "updated_at"
    }
}

struct BrowserDocumentRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func data(forKey key: String) throws -> Data? {
        try BrowserDocumentRow.fetchOne(database, key: key)?.payload
    }

    func save(_ data: Data, forKey key: String) throws {
        try BrowserDocumentRow(
            key: key,
            payload: data,
            updatedAt: Date()
        ).save(database)
    }

    func delete(key: String) throws {
        _ = try BrowserDocumentRow.deleteOne(database, key: key)
    }

    func keys(withPrefix prefix: String) throws -> [String] {
        try String.fetchAll(
            database,
            sql: "SELECT key FROM browser_documents WHERE key LIKE ?",
            arguments: ["\(prefix)%"]
        )
    }

    func value<Value: Decodable>(
        _ type: Value.Type,
        forKey key: String
    ) throws -> Value? {
        guard let data = try data(forKey: key) else { return nil }
        return try JSONDecoder().decode(type, from: data)
    }

    func save<Value: Encodable>(_ value: Value, forKey key: String) throws {
        try save(JSONEncoder().encode(value), forKey: key)
    }
}
