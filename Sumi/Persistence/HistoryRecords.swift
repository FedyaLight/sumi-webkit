import Foundation
import GRDB

struct HistoryEntryRecord: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "history_entries"

    let id: UUID
    let profileID: UUID
    var urlString: String
    var title: String
    var domain: String
    var siteDomain: String?
    var numberOfTotalVisits: Int
    var lastVisit: Date

    private enum CodingKeys: String, CodingKey {
        case id
        case profileID = "profile_id"
        case urlString = "url"
        case title
        case domain
        case siteDomain = "site_domain"
        case numberOfTotalVisits = "visit_count"
        case lastVisit = "last_visit"
    }
}

struct HistoryVisitRow: Codable, Equatable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "history_visits"

    let id: UUID
    let entryID: UUID
    let visitedAt: Date
    let tabID: UUID?

    private enum CodingKeys: String, CodingKey {
        case id
        case entryID = "entry_id"
        case visitedAt = "visited_at"
        case tabID = "tab_id"
    }
}

private struct HistoryVisitJoinedRow: Decodable, FetchableRecord {
    let id: UUID
    let urlString: String
    let title: String
    let visitedAt: Date
    let domain: String
    let siteDomain: String?

    var record: HistoryVisitRecord? {
        guard let url = URL(string: urlString) else { return nil }
        return HistoryVisitRecord(
            id: id,
            url: url,
            title: title,
            visitedAt: visitedAt,
            domain: domain,
            siteDomain: siteDomain
        )
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case urlString = "url_string"
        case title
        case visitedAt = "visited_at"
        case domain
        case siteDomain = "site_domain"
    }
}

struct HistoryRecordStore {
    private let database: Database

    init(database: Database) {
        self.database = database
    }

    func entries(profileID: UUID) throws -> [HistoryEntryRecord] {
        try HistoryEntryRecord
            .filter(Column("profile_id") == profileID)
            .order(Column("last_visit").desc)
            .fetchAll(database)
    }

    func visits(profileID: UUID) throws -> [HistoryVisitRow] {
        try HistoryVisitRow
            .joining(
                required: HistoryVisitRow
                    .belongsTo(HistoryEntryRecord.self)
                    .filter(Column("profile_id") == profileID)
            )
            .order(Column("visited_at").desc)
            .fetchAll(database)
    }

    func recordVisit(
        id: UUID,
        url: URL,
        title: String,
        visitedAt: Date,
        profileID: UUID,
        tabID: UUID?
    ) throws {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let domain = HistoryDomainResolver.normalizedDomain(for: url)

        if var entry = try entry(url: url, profileID: profileID) {
            if !trimmedTitle.isEmpty {
                entry.title = trimmedTitle
            }
            entry.numberOfTotalVisits += 1
            entry.lastVisit = max(entry.lastVisit, visitedAt)
            try entry.update(database)
            try HistoryVisitRow(
                id: id,
                entryID: entry.id,
                visitedAt: visitedAt,
                tabID: tabID
            ).insert(database)
            return
        }

        let entry = HistoryEntryRecord(
            id: UUID(),
            profileID: profileID,
            urlString: url.absoluteString,
            title: trimmedTitle.isEmpty ? domain : trimmedTitle,
            domain: domain,
            siteDomain: HistoryDomainResolver.siteDomain(for: url),
            numberOfTotalVisits: 1,
            lastVisit: visitedAt
        )
        try entry.insert(database)
        try HistoryVisitRow(
            id: id,
            entryID: entry.id,
            visitedAt: visitedAt,
            tabID: tabID
        ).insert(database)
    }

    func updateTitle(
        _ title: String,
        url: URL,
        profileID: UUID
    ) throws {
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayTitle.isEmpty,
              var entry = try entry(url: url, profileID: profileID),
              entry.title != displayTitle else {
            return
        }
        entry.title = displayTitle
        try entry.update(database)
    }

    func fetchVisitChunk(
        query: HistoryQuery,
        profileID: UUID?,
        dateRange: Range<Date>?,
        limit: Int,
        offset: Int
    ) throws -> [HistoryVisitRecord] {
        var clauses: [String] = []
        var arguments = StatementArguments()
        if let profileID {
            clauses.append("e.profile_id = ?")
            arguments += [profileID]
        }
        if let dateRange {
            clauses.append("v.visited_at >= ? AND v.visited_at < ?")
            arguments += [dateRange.lowerBound, dateRange.upperBound]
        }

        switch query.normalizingDomainFilter {
        case .searchTerm(let rawTerm):
            let term = rawTerm.trimmingCharacters(in: .whitespacesAndNewlines)
            if !term.isEmpty {
                let pattern = "%\(term)%"
                clauses.append(
                    "(e.title LIKE ? COLLATE NOCASE OR e.url LIKE ? COLLATE NOCASE OR e.domain LIKE ? COLLATE NOCASE OR e.site_domain LIKE ? COLLATE NOCASE)"
                )
                arguments += [pattern, pattern, pattern, pattern]
            }
        case .domainFilter(let domains):
            if !domains.isEmpty {
                let placeholders = Array(repeating: "?", count: domains.count)
                    .joined(separator: ",")
                clauses.append(
                    "COALESCE(e.site_domain, e.domain) IN (\(placeholders))"
                )
                arguments += StatementArguments(domains.sorted())
            }
        case .visits(let identifiers):
            let ids = identifiers.compactMap { UUID(uuidString: $0.uuid) }
            guard !ids.isEmpty else { return [] }
            let placeholders = Array(repeating: "?", count: ids.count)
                .joined(separator: ",")
            clauses.append("v.id IN (\(placeholders))")
            arguments += StatementArguments(ids)
        case .rangeFilter, .dateFilter, .timeRange:
            break
        }
        arguments += [limit, max(0, offset)]

        let request = SQLRequest<HistoryVisitJoinedRow>(
            sql: """
                SELECT v.id,
                       e.url AS url_string,
                       e.title,
                       v.visited_at,
                       e.domain,
                       e.site_domain
                FROM history_visits v
                JOIN history_entries e ON e.id = v.entry_id
                WHERE \(clauses.isEmpty ? "1" : clauses.joined(separator: " AND "))
                ORDER BY v.visited_at DESC, v.rowid DESC
                LIMIT ? OFFSET ?
                """,
            arguments: arguments
        )
        return try request.fetchAll(database).compactMap(\.record)
    }

    func deleteVisits(ids: Set<UUID>, profileID: UUID?) throws -> Int {
        guard !ids.isEmpty else { return 0 }
        let placeholders = Array(repeating: "?", count: ids.count)
            .joined(separator: ",")
        var arguments = StatementArguments(ids)
        let profileClause: String
        if let profileID {
            profileClause = "AND e.profile_id = ?"
            arguments += [profileID]
        } else {
            profileClause = ""
        }
        let affectedEntryIDs = try UUID.fetchAll(
            database,
            sql: """
                SELECT DISTINCT v.entry_id
                FROM history_visits v
                JOIN history_entries e ON e.id = v.entry_id
                WHERE v.id IN (\(placeholders)) \(profileClause)
                """,
            arguments: arguments
        )
        let deletionProfileClause = profileID == nil
            ? ""
            : "AND entry_id IN (SELECT id FROM history_entries WHERE profile_id = ?)"
        try database.execute(
            sql: """
                DELETE FROM history_visits
                WHERE id IN (\(placeholders))
                \(deletionProfileClause)
                """,
            arguments: arguments
        )
        let deleted = database.changesCount
        for entryID in affectedEntryIDs {
            try repairEntry(id: entryID)
        }
        return deleted
    }

    func clear(profileID: UUID?) throws -> Int {
        guard let profileID else {
            let count = try HistoryVisitRow.fetchCount(database)
            _ = try HistoryEntryRecord.deleteAll(database)
            return count
        }
        let count = try Int.fetchOne(
            database,
            sql: """
                SELECT COUNT(*)
                FROM history_visits v
                JOIN history_entries e ON e.id = v.entry_id
                WHERE e.profile_id = ?
                """,
            arguments: [profileID]
        ) ?? 0
        _ = try HistoryEntryRecord
            .filter(Column("profile_id") == profileID)
            .deleteAll(database)
        return count
    }

    func hasVisits(profileID: UUID) throws -> Bool {
        try Bool.fetchOne(
            database,
            sql: """
                SELECT EXISTS(
                    SELECT 1
                    FROM history_visits v
                    JOIN history_entries e ON e.id = v.entry_id
                    WHERE e.profile_id = ?
                )
                """,
            arguments: [profileID]
        ) ?? false
    }

    func installImportedVisits(
        _ visits: [HistoryImportedVisit],
        profileID: UUID
    ) throws -> HistoryImportedVisitWriter.Receipt {
        var receipt = HistoryImportedVisitWriter.Receipt()
        for visit in visits {
            let existing = try entry(url: visit.url, profileID: profileID)
            if let existing,
               try HistoryVisitRow
                .filter(
                    Column("entry_id") == existing.id
                        && Column("visited_at") == visit.visitedAt
                )
                .fetchCount(database) > 0 {
                continue
            }

            let entryID: UUID
            if var existing {
                receipt.adjustedEntries[existing.id] = receipt.adjustedEntries[
                    existing.id
                ] ?? .init(
                    numberOfTotalVisits: existing.numberOfTotalVisits,
                    lastVisit: existing.lastVisit
                )
                existing.numberOfTotalVisits += 1
                existing.lastVisit = max(existing.lastVisit, visit.visitedAt)
                let displayTitle = visit.title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                if !displayTitle.isEmpty {
                    existing.title = displayTitle
                }
                try existing.update(database)
                entryID = existing.id
            } else {
                let domain = HistoryDomainResolver.normalizedDomain(for: visit.url)
                let displayTitle = visit.title.trimmingCharacters(
                    in: .whitespacesAndNewlines
                )
                let entry = HistoryEntryRecord(
                    id: UUID(),
                    profileID: profileID,
                    urlString: visit.url.absoluteString,
                    title: displayTitle.isEmpty ? domain : displayTitle,
                    domain: domain,
                    siteDomain: HistoryDomainResolver.siteDomain(for: visit.url),
                    numberOfTotalVisits: 1,
                    lastVisit: visit.visitedAt
                )
                try entry.insert(database)
                receipt.createdEntryIDs.append(entry.id)
                entryID = entry.id
            }

            let visitID = UUID()
            try HistoryVisitRow(
                id: visitID,
                entryID: entryID,
                visitedAt: visit.visitedAt,
                tabID: nil
            ).insert(database)
            receipt.insertedVisitIDs.append(visitID)
        }
        return receipt
    }

    func rollbackImportedVisits(
        _ receipt: HistoryImportedVisitWriter.Receipt
    ) throws {
        if !receipt.insertedVisitIDs.isEmpty {
            _ = try HistoryVisitRow
                .filter(receipt.insertedVisitIDs.contains(Column("id")))
                .deleteAll(database)
        }
        if !receipt.createdEntryIDs.isEmpty {
            _ = try HistoryEntryRecord
                .filter(receipt.createdEntryIDs.contains(Column("id")))
                .deleteAll(database)
        }
        for (entryID, prior) in receipt.adjustedEntries {
            guard var entry = try HistoryEntryRecord.fetchOne(
                database,
                key: entryID
            ) else {
                continue
            }
            entry.numberOfTotalVisits = prior.numberOfTotalVisits
            entry.lastVisit = prior.lastVisit
            try entry.update(database)
        }
    }

    private func entry(
        url: URL,
        profileID: UUID
    ) throws -> HistoryEntryRecord? {
        try HistoryEntryRecord
            .filter(
                Column("profile_id") == profileID
                    && Column("url") == url.absoluteString
            )
            .fetchOne(database)
    }

    private func repairEntry(id: UUID) throws {
        guard var entry = try HistoryEntryRecord.fetchOne(database, key: id) else {
            return
        }
        let aggregate = try Row.fetchOne(
            database,
            sql: """
                SELECT COUNT(*) AS count, MAX(visited_at) AS newest
                FROM history_visits
                WHERE entry_id = ?
                """,
            arguments: [id]
        )
        let count: Int = aggregate?["count"] ?? 0
        guard count > 0, let newest: Date = aggregate?["newest"] else {
            _ = try HistoryEntryRecord.deleteOne(database, key: id)
            return
        }
        entry.numberOfTotalVisits = count
        entry.lastVisit = newest
        try entry.update(database)
    }
}
