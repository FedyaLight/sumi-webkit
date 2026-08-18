import Foundation

@MainActor
enum SumiOrphanIdentifierBatch {
    static func runIfNeeded(
        documentKey: String,
        batchSize: Int,
        liveIdentifiers: Set<UUID>,
        database: SumiDatabase,
        fetchIdentifiers: () async -> [UUID],
        removeIdentifier: (UUID) async -> Bool
    ) async throws -> [UUID] {
        var candidates = try persistedCandidates(
            documentKey: documentKey,
            database: database
        )
        if candidates == nil {
            candidates = (await fetchIdentifiers())
                .filter { liveIdentifiers.contains($0) == false }
                .sorted { $0.uuidString < $1.uuidString }
        }
        guard var candidates else { return [] }

        candidates.removeAll { liveIdentifiers.contains($0) }
        guard candidates.isEmpty == false else {
            try persist([], documentKey: documentKey, database: database)
            return []
        }

        let batch = Array(candidates.prefix(batchSize))
        var remaining = Array(candidates.dropFirst(batch.count))
        var removed: [UUID] = []
        for identifier in batch {
            if await removeIdentifier(identifier) {
                removed.append(identifier)
            } else {
                remaining.insert(identifier, at: 0)
            }
        }
        try persist(remaining, documentKey: documentKey, database: database)
        return removed
    }

    private static func persistedCandidates(
        documentKey: String,
        database: SumiDatabase
    ) throws -> [UUID]? {
        try database.read { connection in
            guard let data = try connection.documents.data(forKey: documentKey)
            else {
                return nil
            }
            return try? JSONDecoder().decode([UUID].self, from: data)
        }
    }

    private static func persist(
        _ candidates: [UUID],
        documentKey: String,
        database: SumiDatabase
    ) throws {
        let data = try JSONEncoder().encode(candidates)
        try database.transaction {
            try $0.documents.save(data, forKey: documentKey)
        }
    }
}
