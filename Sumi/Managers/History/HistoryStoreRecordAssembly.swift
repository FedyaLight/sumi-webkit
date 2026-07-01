//
//  HistoryStoreRecordAssembly.swift
//  Sumi
//

import Foundation

enum HistoryStoreRecordAssembly {
    struct VisitSnapshot {
        let id: UUID
        let entryID: UUID
        let visitedAt: Date

        init(_ visit: HistoryVisitEntity) {
            id = visit.id
            entryID = visit.entryID
            visitedAt = visit.visitedAt
        }
    }

    struct EntrySnapshot {
        let id: UUID
        let urlString: String
        let title: String
        let domain: String
        let siteDomain: String?
        let numberOfTotalVisits: Int
        let lastVisit: Date

        init(_ entry: HistoryEntryEntity) {
            id = entry.id
            urlString = entry.urlString
            title = entry.title
            domain = entry.domain
            siteDomain = entry.siteDomain
            numberOfTotalVisits = entry.numberOfTotalVisits
            lastVisit = entry.lastVisit
        }
    }

    struct SiteAccumulator {
        var bestEntry: EntrySnapshot
        var visitCount: Int
    }

    enum SiteEntrySource {
        case resolvedSiteDomain
        case missingSiteDomain
    }

    struct SiteGroup {
        let domain: String
        let accumulator: SiteAccumulator
    }

    struct SiteGroupCursor {
        let source: SiteEntrySource
        var rawOffset = 0
        var bufferedEntries: [EntrySnapshot] = []
        var bufferedIndex = 0
        var pendingEntry: EntrySnapshot?
    }

    static func dateRange(
        for query: HistoryQuery,
        referenceDate: Date,
        calendar: Calendar
    ) -> Range<Date>? {
        switch query {
        case .rangeFilter(.all), .rangeFilter(.allSites), .searchTerm, .domainFilter, .visits:
            return nil
        case .rangeFilter(let range):
            return range.dateRange(for: referenceDate, calendar: calendar)
        case .dateFilter(let date):
            let start = calendar.startOfDay(for: date)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                return nil
            }
            return start..<end
        case .timeRange(let start, let end):
            return start..<end
        }
    }

    static func visitRecords(
        for visits: [VisitSnapshot],
        entries: [EntrySnapshot]
    ) -> [HistoryVisitRecord] {
        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        return visits.compactMap { visit in
            guard let entry = entriesByID[visit.entryID],
                  let url = URL(string: entry.urlString)
            else {
                return nil
            }
            return HistoryVisitRecord(
                id: visit.id,
                url: url,
                title: entry.title,
                visitedAt: visit.visitedAt,
                domain: entry.domain,
                siteDomain: entry.siteDomain
            )
        }
    }

    static func visit(
        _ visit: HistoryVisitRecord,
        matches query: HistoryQuery,
        referenceDate: Date,
        calendar: Calendar
    ) -> Bool {
        switch query {
        case .rangeFilter(.all), .rangeFilter(.allSites):
            return true
        case .rangeFilter(let range):
            guard let dateRange = range.dateRange(for: referenceDate, calendar: calendar) else {
                return true
            }
            return dateRange.contains(visit.visitedAt)
        case .dateFilter(let date):
            let start = calendar.startOfDay(for: date)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                return false
            }
            return start..<end ~= visit.visitedAt
        case .timeRange(let start, let end):
            return start..<end ~= visit.visitedAt
        case .searchTerm(let term):
            let query = SearchTextQuery(term)
            guard !query.isEmpty else { return true }
            return query.matches(visit.title)
                || query.matches(visit.url.absoluteString)
                || query.matches(visit.domain)
                || (visit.siteDomain.map(query.matches) ?? false)
        case .domainFilter(let domains):
            guard !domains.isEmpty else { return true }
            let normalizedDomains = HistoryDomainResolver.siteDomains(for: domains)
            let visitDomain = visit.siteDomain
                ?? HistoryDomainResolver.siteDomain(forDomain: visit.domain)
                ?? visit.domain
            return normalizedDomains.contains(visitDomain)
        case .visits(let identifiers):
            guard !identifiers.isEmpty else { return false }
            return Set(identifiers).contains(
                VisitIdentifier(uuid: visit.id.uuidString, url: visit.url, date: visit.visitedAt)
            )
        }
    }

    static func visibleKey(for record: HistoryVisitRecord, calendar: Calendar) -> String {
        let dayKey = calendar.startOfDay(for: record.visitedAt).timeIntervalSince1970
        return "\(dayKey)|\(record.url.absoluteString)"
    }

    static func nextSiteDomain(
        resolvedGroup: SiteGroup?,
        missingGroup: SiteGroup?
    ) -> String? {
        switch (resolvedGroup?.domain, missingGroup?.domain) {
        case (.some(let resolvedDomain), .some(let missingDomain)):
            return min(resolvedDomain, missingDomain)
        case (.some(let resolvedDomain), .none):
            return resolvedDomain
        case (.none, .some(let missingDomain)):
            return missingDomain
        case (.none, .none):
            return nil
        }
    }

    static func merge(
        _ incoming: SiteAccumulator,
        into accumulator: inout SiteAccumulator?,
        domain: String
    ) {
        guard var current = accumulator else {
            accumulator = incoming
            return
        }

        current.visitCount += incoming.visitCount
        if comparePreferredEntries(incoming.bestEntry, current.bestEntry, for: domain) {
            current.bestEntry = incoming.bestEntry
        }
        accumulator = current
    }

    static func siteRecord(
        domain: String,
        accumulator: SiteAccumulator
    ) -> HistorySiteRecord? {
        let bestEntry = accumulator.bestEntry
        guard let url = URL(string: bestEntry.urlString) else { return nil }

        let title = bestEntry.title.isEmpty ? bestEntry.urlString : bestEntry.title
        return HistorySiteRecord(
            id: domain,
            domain: domain,
            url: url,
            title: title,
            visitCount: accumulator.visitCount
        )
    }

    static func effectiveSiteDomain(for entry: EntrySnapshot) -> String {
        entry.siteDomain
            ?? HistoryDomainResolver.siteDomain(forDomain: entry.domain)
            ?? entry.domain
    }

    static func siteMatches(_ site: HistorySiteRecord, query: SearchTextQuery) -> Bool {
        query.matches(site.title)
            || query.matches(site.url.absoluteString)
            || query.matches(site.domain)
    }

    static func comparePreferredEntries(
        _ lhs: EntrySnapshot,
        _ rhs: EntrySnapshot,
        for domain: String
    ) -> Bool {
        let lhsHasTitle = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let rhsHasTitle = rhs.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if lhsHasTitle != rhsHasTitle {
            return lhsHasTitle && !rhsHasTitle
        }

        let lhsURL = URL(string: lhs.urlString)
        let rhsURL = URL(string: rhs.urlString)
        let lhsHTTPS = lhsURL?.scheme?.lowercased() == "https"
        let rhsHTTPS = rhsURL?.scheme?.lowercased() == "https"
        if lhsHTTPS != rhsHTTPS {
            return lhsHTTPS && !rhsHTTPS
        }

        let lhsRoot = lhsURL.map { $0.path.isEmpty || $0.path == "/" } ?? false
        let rhsRoot = rhsURL.map { $0.path.isEmpty || $0.path == "/" } ?? false
        if lhsRoot != rhsRoot {
            return lhsRoot && !rhsRoot
        }

        let lhsHost = lhsURL?.host?.lowercased().trimmingPrefix("www.") ?? ""
        let rhsHost = rhsURL?.host?.lowercased().trimmingPrefix("www.") ?? ""
        let lhsMatchesDomain = lhsHost == domain
        let rhsMatchesDomain = rhsHost == domain
        if lhsMatchesDomain != rhsMatchesDomain {
            return lhsMatchesDomain && !rhsMatchesDomain
        }

        return lhs.lastVisit > rhs.lastVisit
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
