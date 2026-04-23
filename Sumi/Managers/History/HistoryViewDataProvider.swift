import Foundation

@MainActor
final class HistoryViewDataProvider {
    private let store: HistoryStore
    private let currentProfileIdProvider: @MainActor () -> UUID?
    private let referenceDateProvider: @MainActor () -> Date
    private let calendar: Calendar
    private let relativeDayFormatter: DateFormatter
    private let timeFormatter: DateFormatter

    private(set) var rawVisits: [HistoryVisitRecord] = []
    private var allItems: [HistoryListItem] = []
    private var dayItemsByRange: [HistoryRange: [HistoryListItem]] = [:]
    private var itemsByDomain: [String: [HistoryVisitRecord]] = [:]
    private var refreshGeneration: UInt64 = 0
    private var rangesCache: [HistoryRangeCount] = [
        .init(id: .all, count: 0),
        .init(id: .allSites, count: 0),
    ]

    init(
        store: HistoryStore,
        currentProfileIdProvider: @escaping @MainActor () -> UUID?,
        referenceDateProvider: @escaping @MainActor () -> Date = { Date() },
        calendar: Calendar = .autoupdatingCurrent
    ) {
        self.store = store
        self.currentProfileIdProvider = currentProfileIdProvider
        self.referenceDateProvider = referenceDateProvider
        self.calendar = calendar

        let relativeDayFormatter = DateFormatter()
        relativeDayFormatter.calendar = calendar
        relativeDayFormatter.dateStyle = .medium
        relativeDayFormatter.timeStyle = .none
        self.relativeDayFormatter = relativeDayFormatter

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        self.timeFormatter = timeFormatter
    }

    var ranges: [HistoryRangeCount] {
        rangesCache
    }

    var canClearHistory: Bool {
        !rawVisits.isEmpty
    }

    func refreshData() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let loadedVisits: [HistoryVisitRecord]
        do {
            loadedVisits = try await store.visits(profileId: currentProfileIdProvider())
        } catch {
            RuntimeDiagnostics.emit("Error loading history visits: \(error)")
            loadedVisits = []
        }
        guard generation == refreshGeneration else { return }
        rawVisits = loadedVisits
        rebuildCaches(referenceDate: referenceDateProvider())
    }

    func items(for query: HistoryQuery) -> [HistoryListItem] {
        items(matching: query)
    }

    func sections(for query: HistoryQuery) -> [HistorySection] {
        let items = items(matching: query)
        if case .rangeFilter(.allSites) = query {
            return [.init(id: "sites", title: HistoryRange.allSites.title, items: items)]
        }

        var sections: [HistorySection] = []
        var itemsByTitle: [String: [HistoryListItem]] = [:]
        for item in items {
            let title = item.relativeDay.isEmpty ? "History" : item.relativeDay
            if itemsByTitle[title] == nil {
                sections.append(.init(id: title, title: title, items: []))
            }
            itemsByTitle[title, default: []].append(item)
        }

        return sections.map { section in
            .init(id: section.id, title: section.title, items: itemsByTitle[section.id] ?? [])
        }
    }

    func deleteVisits(matching query: HistoryQuery) async {
        do {
            let ids = matchingRecordIDs(for: query)
            _ = try await store.deleteVisits(withIDs: ids, profileId: currentProfileIdProvider())
        } catch {
            RuntimeDiagnostics.emit("Error deleting history visits: \(error)")
        }
        await refreshData()
    }

    func deleteSelection(
        visitIDs: [VisitIdentifier],
        domains: Set<String>
    ) async {
        do {
            var ids = Set<UUID>()
            if !visitIDs.isEmpty {
                ids.formUnion(matchingRecordIDs(for: .visits(visitIDs)))
            }
            if !domains.isEmpty {
                ids.formUnion(matchingRecordIDs(for: .domainFilter(domains)))
            }
            guard !ids.isEmpty else {
                await refreshData()
                return
            }
            _ = try await store.deleteVisits(withIDs: ids, profileId: currentProfileIdProvider())
        } catch {
            RuntimeDiagnostics.emit("Error deleting selected history visits: \(error)")
        }
        await refreshData()
    }

    func clearAll() async {
        do {
            _ = try await store.clearAll(profileId: currentProfileIdProvider())
        } catch {
            RuntimeDiagnostics.emit("Error clearing history visits: \(error)")
        }
        await refreshData()
    }

    func visits(matching query: HistoryQuery) async -> [HistoryVisitRecord] {
        matchingVisits(for: query)
    }

    func preferredURL(forSiteDomain domain: String) -> URL? {
        bestRecord(for: itemsByDomain[domain] ?? [])?.url
            ?? bestRecord(for: rawVisits.filter { ($0.siteDomain ?? $0.domain) == domain })?.url
    }

    func recentVisitedItems(maxCount: Int) -> [HistoryListItem] {
        let referenceDate = referenceDateProvider()
        return Array(
            allItems
                .filter { item in
                    guard let visitedAt = item.visitedAt else { return false }
                    return calendar.isDate(visitedAt, inSameDayAs: referenceDate)
                }
                .prefix(maxCount)
        )
    }

    func searchSuggestions(matching query: String, limit: Int) -> [HistoryListItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }
        return Array(
            allItems
                .filter { $0.matches(query) }
                .sorted { ($0.visitedAt ?? .distantPast) > ($1.visitedAt ?? .distantPast) }
                .prefix(limit)
        )
    }

    private func rebuildCaches(referenceDate: Date) {
        let visibleVisits = deduplicatedVisibleVisits(from: rawVisits)
        allItems = []
        dayItemsByRange = [:]
        itemsByDomain = Dictionary(grouping: rawVisits) { $0.siteDomain ?? $0.domain }

        let groupedByDay = Dictionary(grouping: visibleVisits) {
            calendar.startOfDay(for: $0.visitedAt)
        }

        for day in groupedByDay.keys.sorted(by: >) {
            guard let range = HistoryRange(
                date: day,
                referenceDate: referenceDate,
                calendar: calendar
            ) else {
                continue
            }

            let records = (groupedByDay[day] ?? []).sorted { $0.visitedAt > $1.visitedAt }
            let items = records.map { makeHistoryItem(from: $0, referenceDate: referenceDate) }
            dayItemsByRange[range, default: []].append(contentsOf: items)
            allItems.append(contentsOf: items)
        }

        let sitesItems = makeSitesItems()
        dayItemsByRange[.allSites] = sitesItems

        let displayedRanges = HistoryRange.displayedRanges(
            for: referenceDate,
            calendar: calendar
        )
        let trimmedRanges = Array(
            displayedRanges.reversed()
                .drop(while: { dayItemsByRange[$0]?.isEmpty != false })
                .reversed()
        )

        var computedRanges = trimmedRanges.map {
            HistoryRangeCount(id: $0, count: dayItemsByRange[$0]?.count ?? 0)
        }
        computedRanges.insert(.init(id: .all, count: allItems.count), at: 0)
        computedRanges.append(.init(id: .allSites, count: sitesItems.count))
        rangesCache = computedRanges
    }

    private func items(matching query: HistoryQuery) -> [HistoryListItem] {
        switch query {
        case .rangeFilter(.all):
            return allItems
        case .rangeFilter(let range):
            return dayItemsByRange[range] ?? []
        case .dateFilter(let date):
            let start = calendar.startOfDay(for: date)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                return []
            }
            return allItems.filter {
                guard let visitedAt = $0.visitedAt else { return false }
                return start..<end ~= visitedAt
            }
        case .searchTerm(let term):
            guard !term.isEmpty else { return allItems }
            return allItems.filter { $0.matches(term) }
        case .domainFilter(let domains):
            guard !domains.isEmpty else { return allItems }
            return allItems.filter { $0.matchesDomains(domains) }
        case .visits(let identifiers):
            guard !identifiers.isEmpty else { return [] }
            let identifierSet = Set(identifiers)
            return allItems.filter { item in
                guard let visitID = item.visitID else { return false }
                return identifierSet.contains(visitID)
            }
        }
    }

    private func matchingVisits(for query: HistoryQuery) -> [HistoryVisitRecord] {
        switch query {
        case .rangeFilter(.all):
            return rawVisits
        case .rangeFilter(.allSites):
            return rawVisits
        case .rangeFilter(let range):
            guard let dateRange = range.dateRange(for: referenceDateProvider(), calendar: calendar) else {
                return rawVisits
            }
            return rawVisits.filter { dateRange.contains($0.visitedAt) }
        case .dateFilter(let date):
            let start = calendar.startOfDay(for: date)
            guard let end = calendar.date(byAdding: .day, value: 1, to: start) else {
                return []
            }
            return rawVisits.filter { start..<end ~= $0.visitedAt }
        case .searchTerm(let term):
            guard !term.isEmpty else { return rawVisits }
            return rawVisits.filter { visitMatchesSearchTerm($0, term: term) }
        case .domainFilter(let domains):
            guard !domains.isEmpty else { return rawVisits }
            return rawVisits.filter { domains.contains($0.siteDomain ?? $0.domain) }
        case .visits(let identifiers):
            let identifierSet = Set(identifiers)
            return rawVisits.filter { visit in
                identifierSet.contains(
                    VisitIdentifier(uuid: visit.id.uuidString, url: visit.url, date: visit.visitedAt)
                )
            }
        }
    }

    private func matchingRecordIDs(for query: HistoryQuery) -> Set<UUID> {
        Set(matchingVisits(for: query).map(\.id))
    }

    private func deduplicatedVisibleVisits(from visits: [HistoryVisitRecord]) -> [HistoryVisitRecord] {
        var seenKeys = Set<String>()
        var results: [HistoryVisitRecord] = []

        for visit in visits.sorted(by: { $0.visitedAt > $1.visitedAt }) {
            let dayKey = calendar.startOfDay(for: visit.visitedAt).timeIntervalSince1970
            let key = "\(dayKey)|\(visit.url.absoluteString)"
            if seenKeys.insert(key).inserted {
                results.append(visit)
            }
        }

        return results
    }

    private func makeHistoryItem(
        from visit: HistoryVisitRecord,
        referenceDate: Date
    ) -> HistoryListItem {
        let visitID = VisitIdentifier(
            uuid: visit.id.uuidString,
            url: visit.url,
            date: visit.visitedAt
        )

        return HistoryListItem(
            id: visitID.description,
            visitID: visitID,
            url: visit.url,
            title: visit.title,
            domain: visit.domain,
            siteDomain: visit.siteDomain,
            visitedAt: visit.visitedAt,
            relativeDay: relativeDayString(for: visit.visitedAt, referenceDate: referenceDate),
            timeText: timeFormatter.string(from: visit.visitedAt),
            visitCount: 1,
            isSiteAggregate: false
        )
    }

    private func makeSitesItems() -> [HistoryListItem] {
        itemsByDomain.keys.sorted().compactMap { domain in
            guard let url = preferredURL(forSiteDomain: domain) else {
                return nil
            }
            let title = bestTitle(for: itemsByDomain[domain] ?? [], domain: domain)
            return HistoryListItem(
                id: "site:\(domain)",
                visitID: nil,
                url: url,
                title: title,
                domain: domain,
                siteDomain: domain,
                visitedAt: nil,
                relativeDay: "",
                timeText: "",
                visitCount: itemsByDomain[domain]?.count ?? 0,
                isSiteAggregate: true
            )
        }
    }

    private func bestTitle(for records: [HistoryVisitRecord], domain: String) -> String {
        if let bestRecord = bestRecord(for: records) {
            return bestRecord.title.isEmpty ? bestRecord.url.absoluteString : bestRecord.title
        }
        return domain
    }

    private func bestRecord(for records: [HistoryVisitRecord]) -> HistoryVisitRecord? {
        records
            .sorted(by: comparePreferredRecords)
            .first
    }

    private func comparePreferredRecords(
        _ lhs: HistoryVisitRecord,
        _ rhs: HistoryVisitRecord
    ) -> Bool {
        let lhsHasTitle = lhs.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        let rhsHasTitle = rhs.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false
        if lhsHasTitle != rhsHasTitle {
            return lhsHasTitle && !rhsHasTitle
        }

        let lhsHTTPS = lhs.url.scheme?.lowercased() == "https"
        let rhsHTTPS = rhs.url.scheme?.lowercased() == "https"
        if lhsHTTPS != rhsHTTPS {
            return lhsHTTPS && !rhsHTTPS
        }

        let lhsRoot = (lhs.url.path.isEmpty || lhs.url.path == "/")
        let rhsRoot = (rhs.url.path.isEmpty || rhs.url.path == "/")
        if lhsRoot != rhsRoot {
            return lhsRoot && !rhsRoot
        }

        let lhsHost = lhs.url.host?.lowercased().trimmingPrefix("www.") ?? ""
        let rhsHost = rhs.url.host?.lowercased().trimmingPrefix("www.") ?? ""
        if let domain = lhs.siteDomain ?? rhs.siteDomain {
            let lhsMatchesDomain = lhsHost == domain
            let rhsMatchesDomain = rhsHost == domain
            if lhsMatchesDomain != rhsMatchesDomain {
                return lhsMatchesDomain && !rhsMatchesDomain
            }
        }

        return lhs.visitedAt > rhs.visitedAt
    }

    private func visitMatchesSearchTerm(
        _ visit: HistoryVisitRecord,
        term: String
    ) -> Bool {
        let needle = term.lowercased()
        return visit.title.lowercased().contains(needle)
            || visit.url.absoluteString.lowercased().contains(needle)
            || visit.domain.lowercased().contains(needle)
            || (visit.siteDomain?.lowercased().contains(needle) ?? false)
    }

    private func relativeDayString(
        for date: Date,
        referenceDate: Date
    ) -> String {
        if calendar.isDate(date, inSameDayAs: referenceDate) {
            return HistoryRange.today.title
        }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: referenceDate),
           calendar.isDate(date, inSameDayAs: yesterday)
        {
            return HistoryRange.yesterday.title
        }
        if let range = HistoryRange(
            date: date,
            referenceDate: referenceDate,
            calendar: calendar
        ), range != .older {
            return range.title
        }
        return relativeDayFormatter.string(from: date)
    }
}

private extension String {
    func trimmingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
