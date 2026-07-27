import Foundation

actor HistoryStore {
    static let defaultHistoryPageLimit = 100
    static let defaultSuggestionLimit = 20
    static let defaultRecentMenuLimit = 12

    private static let scanChunkSize = 256
    private let database: SumiDatabase

    init(database: SumiDatabase) {
        self.database = database
    }

    @discardableResult
    func recordVisit(
        id: UUID = UUID(),
        url: URL,
        title: String,
        visitedAt: Date,
        profileId: UUID?,
        tabId: UUID? = nil
    ) throws -> UUID {
        let profileID = try requiredProfileID(profileId)
        try database.transaction {
            try $0.history.recordVisit(
                id: id,
                url: url,
                title: title,
                visitedAt: visitedAt,
                profileID: profileID,
                tabID: tabId
            )
        }
        return id
    }

    func installImportedVisits(
        _ visits: [HistoryImportedVisit],
        profileId: UUID?
    ) throws -> HistoryImportedVisitWriter.Receipt {
        let profileID = try requiredProfileID(profileId)
        return try database.transaction {
            try $0.history.installImportedVisits(visits, profileID: profileID)
        }
    }

    func rollbackImportedVisits(
        _ receipt: HistoryImportedVisitWriter.Receipt
    ) throws {
        try database.transaction {
            try $0.history.rollbackImportedVisits(receipt)
        }
    }

    func updateTitleIfNeeded(
        title: String,
        url: URL,
        profileId: UUID?
    ) throws {
        let profileID = try requiredProfileID(profileId)
        try database.transaction {
            try $0.history.updateTitle(title, url: url, profileID: profileID)
        }
    }

    func fetchRecentHistory(
        profileId: UUID?,
        limit: Int,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> [HistoryVisitRecord] {
        try fetchHistoryPage(
            query: .rangeFilter(.today),
            profileId: profileId,
            limit: limit,
            offset: 0,
            referenceDate: referenceDate,
            calendar: calendar
        ).records
    }

    func searchHistory(
        query: String,
        profileId: UUID?,
        limit: Int,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> [HistoryVisitRecord] {
        try fetchHistoryPage(
            query: .searchTerm(query),
            profileId: profileId,
            limit: limit,
            offset: 0,
            referenceDate: referenceDate,
            calendar: calendar
        ).records
    }

    func fetchHistoryPage(
        query: HistoryQuery,
        profileId: UUID?,
        limit: Int,
        offset: Int,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> HistoryVisitPage {
        guard limit > 0 else {
            return HistoryVisitPage(
                records: [],
                nextOffset: max(0, offset),
                hasMore: false
            )
        }
        let normalizedQuery = query.normalizingDomainFilter
        let dateRange = HistoryStoreRecordAssembly.dateRange(
            for: normalizedQuery,
            referenceDate: referenceDate,
            calendar: calendar
        )
        let startOffset = max(0, offset)
        var rawOffset = 0
        var visibleOffset = 0
        var records: [HistoryVisitRecord] = []
        var seenVisibleKeys = Set<String>()

        while true {
            let chunk = try database.read {
                try $0.history.fetchVisitChunk(
                    query: normalizedQuery,
                    profileID: profileId,
                    dateRange: dateRange,
                    limit: Self.scanChunkSize,
                    offset: rawOffset
                )
            }
            guard !chunk.isEmpty else {
                return HistoryVisitPage(
                    records: records,
                    nextOffset: startOffset + records.count,
                    hasMore: false
                )
            }
            rawOffset += chunk.count

            for record in chunk where HistoryStoreRecordAssembly.visit(
                record,
                matches: normalizedQuery,
                referenceDate: referenceDate,
                calendar: calendar
            ) {
                let key = HistoryStoreRecordAssembly.visibleKey(
                    for: record,
                    calendar: calendar
                )
                guard seenVisibleKeys.insert(key).inserted else { continue }
                guard visibleOffset >= startOffset else {
                    visibleOffset += 1
                    continue
                }
                if records.count < limit {
                    records.append(record)
                    visibleOffset += 1
                } else {
                    return HistoryVisitPage(
                        records: records,
                        nextOffset: startOffset + records.count,
                        hasMore: true
                    )
                }
            }
        }
    }

    func fetchVisitRecordsForExplicitAction(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> [HistoryVisitRecord] {
        let normalizedQuery = query.normalizingDomainFilter
        let dateRange = HistoryStoreRecordAssembly.dateRange(
            for: normalizedQuery,
            referenceDate: referenceDate,
            calendar: calendar
        )
        var offset = 0
        var records: [HistoryVisitRecord] = []
        while true {
            let chunk = try database.read {
                try $0.history.fetchVisitChunk(
                    query: normalizedQuery,
                    profileID: profileId,
                    dateRange: dateRange,
                    limit: Self.scanChunkSize,
                    offset: offset
                )
            }
            guard !chunk.isEmpty else { return records }
            offset += chunk.count
            records.append(contentsOf: chunk.filter {
                HistoryStoreRecordAssembly.visit(
                    $0,
                    matches: normalizedQuery,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            })
        }
    }

    func countVisits(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Int {
        try fetchVisitRecordsForExplicitAction(
            matching: query,
            profileId: profileId,
            referenceDate: referenceDate,
            calendar: calendar
        ).count
    }

    func hasVisits(profileId: UUID?) throws -> Bool {
        let profileID = try requiredProfileID(profileId)
        return try database.read {
            try $0.history.hasVisits(profileID: profileID)
        }
    }

    func domains(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Set<String> {
        if case .domainFilter(let domains) = query {
            return HistoryDomainResolver.siteDomains(for: domains)
        }
        return Set(
            try fetchVisitRecordsForExplicitAction(
                matching: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: calendar
            ).map { $0.siteDomain ?? $0.domain }
        )
    }

    func fetchVisitedURLs(profileId: UUID?) throws -> [URL] {
        let profileID = try requiredProfileID(profileId)
        return try database.read {
            try $0.history.entries(profileID: profileID)
                .compactMap { URL(string: $0.urlString) }
        }
    }

    func fetchSitePage(
        profileId: UUID?,
        searchTerm: String?,
        limit: Int,
        offset: Int
    ) throws -> HistorySitePage {
        guard limit > 0 else {
            return HistorySitePage(
                sites: [],
                nextOffset: max(0, offset),
                hasMore: false
            )
        }
        let query = searchTerm.map(SearchTextQuery.init)
        let sites = try siteRecords(profileId: profileId)
            .filter { site in
                guard let query, !query.isEmpty else { return true }
                return HistoryStoreRecordAssembly.siteMatches(site, query: query)
            }
            .sorted {
                $0.domain.localizedStandardCompare($1.domain) == .orderedAscending
            }
        let start = max(0, offset)
        let page = Array(sites.dropFirst(start).prefix(limit))
        return HistorySitePage(
            sites: page,
            nextOffset: start + page.count,
            hasMore: sites.count > start + page.count
        )
    }

    func fetchTopSites(
        profileId: UUID?,
        limit: Int
    ) throws -> [HistorySiteRecord] {
        guard limit > 0 else { return [] }
        return Array(
            try siteRecords(profileId: profileId)
                .sorted {
                    if $0.visitCount != $1.visitCount {
                        return $0.visitCount > $1.visitCount
                    }
                    return $0.domain < $1.domain
                }
                .prefix(limit)
        )
    }

    func remainingHistoryHosts(
        forSiteDomains siteDomains: Set<String>,
        profileId: UUID?
    ) throws -> Set<String> {
        let targets = HistoryDomainResolver.siteDomains(for: siteDomains)
        guard !targets.isEmpty else { return [] }
        let profileID = try requiredProfileID(profileId)
        return try database.read {
            Set(
                try $0.history.entries(profileID: profileID).compactMap { entry in
                    let site = entry.siteDomain
                        ?? HistoryDomainResolver.siteDomain(forDomain: entry.domain)
                        ?? entry.domain
                    guard targets.contains(site),
                          let url = URL(string: entry.urlString) else {
                        return nil
                    }
                    let host = HistoryDomainResolver.normalizedDomain(for: url)
                    return host.isEmpty ? nil : host
                }
            )
        }
    }

    @discardableResult
    func deleteVisits(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Int {
        switch query {
        case .rangeFilter(.all), .rangeFilter(.allSites):
            return try clearAllExplicit(profileId: profileId)
        default:
            let records = try fetchVisitRecordsForExplicitAction(
                matching: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: calendar
            )
            return try deleteVisits(
                withIDs: Set(records.map(\.id)),
                profileId: profileId
            )
        }
    }

    @discardableResult
    func deleteVisits(
        withIDs ids: Set<UUID>,
        profileId: UUID?
    ) throws -> Int {
        try database.transaction {
            try $0.history.deleteVisits(ids: ids, profileID: profileId)
        }
    }

    @discardableResult
    func clearAllExplicit(profileId: UUID?) throws -> Int {
        try database.transaction {
            try $0.history.clear(profileID: profileId)
        }
    }

    private func siteRecords(profileId: UUID?) throws -> [HistorySiteRecord] {
        let profileID = try requiredProfileID(profileId)
        let entries = try database.read {
            try $0.history.entries(profileID: profileID)
        }
        var accumulators: [String: HistoryStoreRecordAssembly.SiteAccumulator] = [:]
        for entry in entries {
            let snapshot = HistoryStoreRecordAssembly.EntrySnapshot(
                id: entry.id,
                urlString: entry.urlString,
                title: entry.title,
                domain: entry.domain,
                siteDomain: entry.siteDomain,
                numberOfTotalVisits: entry.numberOfTotalVisits,
                lastVisit: entry.lastVisit
            )
            let domain = HistoryStoreRecordAssembly.effectiveSiteDomain(for: snapshot)
            if var accumulator = accumulators[domain] {
                accumulator.visitCount += snapshot.numberOfTotalVisits
                if HistoryStoreRecordAssembly.comparePreferredEntries(
                    snapshot,
                    accumulator.bestEntry,
                    for: domain
                ) {
                    accumulator.bestEntry = snapshot
                }
                accumulators[domain] = accumulator
            } else {
                accumulators[domain] = .init(
                    bestEntry: snapshot,
                    visitCount: snapshot.numberOfTotalVisits
                )
            }
        }
        return accumulators.compactMap {
            HistoryStoreRecordAssembly.siteRecord(
                domain: $0.key,
                accumulator: $0.value
            )
        }
    }

    private func requiredProfileID(_ profileID: UUID?) throws -> UUID {
        guard let profileID else {
            throw SumiDatabaseError.historyRequiresProfile
        }
        return profileID
    }
}
