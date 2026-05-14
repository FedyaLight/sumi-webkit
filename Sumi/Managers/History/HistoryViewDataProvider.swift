import Foundation

@MainActor
final class HistoryViewDataProvider {
    private let store: HistoryStore
    private let currentProfileIdProvider: @MainActor () -> UUID?
    private let referenceDateProvider: @MainActor () -> Date
    private let calendar: Calendar
    private let timeFormatter: DateFormatter

    private var refreshGeneration: UInt64 = 0
    private var rangesCache: [HistoryRangeCount] = [
        .init(id: .all),
        .init(id: .allSites),
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

        let timeFormatter = DateFormatter()
        timeFormatter.calendar = calendar
        timeFormatter.dateStyle = .none
        timeFormatter.timeStyle = .short
        self.timeFormatter = timeFormatter
    }

    var ranges: [HistoryRangeCount] {
        rangesCache
    }

    func refreshData() async {
        refreshGeneration &+= 1
        let generation = refreshGeneration
        let profileId = currentProfileIdProvider()

        do {
            _ = try await store.hasVisits(profileId: profileId)
            let loadedRanges = [
                HistoryRangeCount(id: .all),
                HistoryRangeCount(id: .allSites),
            ]
            guard generation == refreshGeneration else { return }
            rangesCache = loadedRanges
        } catch {
            RuntimeDiagnostics.emit("Error loading bounded history summary: \(error)")
            guard generation == refreshGeneration else { return }
            rangesCache = [
                .init(id: .all),
                .init(id: .allSites),
            ]
        }
    }

    func hasHistory() async -> Bool {
        do {
            return try await store.hasVisits(profileId: currentProfileIdProvider())
        } catch {
            RuntimeDiagnostics.emit("Error checking history availability: \(error)")
            return false
        }
    }

    func page(
        for query: HistoryQuery,
        searchTerm: String? = nil,
        limit: Int,
        offset: Int
    ) async -> HistoryListPage {
        let trimmedSearch = searchTerm?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""

        if case .rangeFilter(.allSites) = query {
            return await sitePage(searchTerm: trimmedSearch, limit: limit, offset: offset)
        }

        if !trimmedSearch.isEmpty, query != .rangeFilter(.all) {
            return await filteredPage(
                for: query,
                searchTerm: trimmedSearch,
                limit: limit,
                offset: offset
            )
        }

        let effectiveQuery: HistoryQuery = trimmedSearch.isEmpty
            ? query
            : .searchTerm(trimmedSearch)
        return await historyPage(for: effectiveQuery, limit: limit, offset: offset)
    }

    func visitDomains(for query: HistoryQuery) async -> Set<String> {
        do {
            return try await store.domains(
                matching: query,
                profileId: currentProfileIdProvider(),
                referenceDate: referenceDateProvider(),
                calendar: calendar
            )
        } catch {
            RuntimeDiagnostics.emit("Error loading history domains: \(error)")
            return []
        }
    }

    func remainingHistoryHosts(forSiteDomains domains: Set<String>) async -> Set<String> {
        do {
            return try await store.remainingHistoryHosts(
                forSiteDomains: domains,
                profileId: currentProfileIdProvider()
            )
        } catch {
            RuntimeDiagnostics.emit("Error loading remaining history hosts: \(error)")
            return []
        }
    }

    func deleteVisits(matching query: HistoryQuery) async {
        do {
            _ = try await store.deleteVisits(
                matching: query,
                profileId: currentProfileIdProvider(),
                referenceDate: referenceDateProvider(),
                calendar: calendar
            )
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
            if !visitIDs.isEmpty {
                _ = try await store.deleteVisits(
                    matching: .visits(visitIDs),
                    profileId: currentProfileIdProvider(),
                    referenceDate: referenceDateProvider(),
                    calendar: calendar
                )
            }
            if !domains.isEmpty {
                _ = try await store.deleteVisits(
                    matching: .domainFilter(domains),
                    profileId: currentProfileIdProvider(),
                    referenceDate: referenceDateProvider(),
                    calendar: calendar
                )
            }
        } catch {
            RuntimeDiagnostics.emit("Error deleting selected history visits: \(error)")
        }
        await refreshData()
    }

    func clearAll() async {
        do {
            _ = try await store.clearAllExplicit(profileId: currentProfileIdProvider())
        } catch {
            RuntimeDiagnostics.emit("Error clearing history visits: \(error)")
        }
        await refreshData()
    }

    func recentVisitedItems(maxCount: Int) async -> [HistoryListItem] {
        do {
            let records = try await store.fetchRecentHistory(
                profileId: currentProfileIdProvider(),
                limit: maxCount,
                referenceDate: referenceDateProvider(),
                calendar: calendar
            )
            return records.map(makeHistoryItem)
        } catch {
            RuntimeDiagnostics.emit("Error loading recent history menu items: \(error)")
            return []
        }
    }

    func searchSuggestions(matching query: String, limit: Int) async -> [HistoryListItem] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return []
        }

        do {
            let records = try await store.searchHistory(
                query: query,
                profileId: currentProfileIdProvider(),
                limit: limit,
                referenceDate: referenceDateProvider(),
                calendar: calendar
            )
            return records.map(makeHistoryItem)
        } catch {
            RuntimeDiagnostics.emit("Error loading history suggestions: \(error)")
            return []
        }
    }

    func topVisitedSites(limit: Int) async -> [HistoryListItem] {
        do {
            let records = try await store.fetchTopSites(
                profileId: currentProfileIdProvider(),
                limit: limit
            )
            return records.map(makeSiteItem)
        } catch {
            RuntimeDiagnostics.emit("Error loading top visited sites: \(error)")
            return []
        }
    }

    private func historyPage(
        for query: HistoryQuery,
        limit: Int,
        offset: Int
    ) async -> HistoryListPage {
        do {
            let page = try await store.fetchHistoryPage(
                query: query,
                profileId: currentProfileIdProvider(),
                limit: limit,
                offset: offset,
                referenceDate: referenceDateProvider(),
                calendar: calendar
            )
            return HistoryListPage(
                items: page.records.map(makeHistoryItem),
                nextOffset: page.nextOffset,
                hasMore: page.hasMore
            )
        } catch {
            RuntimeDiagnostics.emit("Error loading history page: \(error)")
            return HistoryListPage(items: [], nextOffset: offset, hasMore: false)
        }
    }

    private func filteredPage(
        for query: HistoryQuery,
        searchTerm: String,
        limit: Int,
        offset: Int
    ) async -> HistoryListPage {
        var baseOffset = 0
        var matchedOffset = 0
        var items: [HistoryListItem] = []
        let startOffset = max(0, offset)

        while true {
            let page = await historyPage(
                for: query,
                limit: max(limit, HistoryStore.defaultHistoryPageLimit),
                offset: baseOffset
            )
            for item in page.items where item.matches(searchTerm) {
                guard matchedOffset >= startOffset else {
                    matchedOffset += 1
                    continue
                }
                if items.count < limit {
                    items.append(item)
                    matchedOffset += 1
                } else {
                    return HistoryListPage(
                        items: items,
                        nextOffset: startOffset + items.count,
                        hasMore: true
                    )
                }
            }

            guard page.hasMore else {
                return HistoryListPage(
                    items: items,
                    nextOffset: startOffset + items.count,
                    hasMore: false
                )
            }
            baseOffset = page.nextOffset
        }
    }

    private func sitePage(
        searchTerm: String,
        limit: Int,
        offset: Int
    ) async -> HistoryListPage {
        do {
            let page = try await store.fetchSitePage(
                profileId: currentProfileIdProvider(),
                searchTerm: searchTerm,
                limit: limit,
                offset: offset
            )
            return HistoryListPage(
                items: page.sites.map(makeSiteItem),
                nextOffset: page.nextOffset,
                hasMore: page.hasMore
            )
        } catch {
            RuntimeDiagnostics.emit("Error loading history sites page: \(error)")
            return HistoryListPage(items: [], nextOffset: offset, hasMore: false)
        }
    }

    private func makeHistoryItem(from visit: HistoryVisitRecord) -> HistoryListItem {
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
            timeText: timeFormatter.string(from: visit.visitedAt),
            visitCount: 1,
            isSiteAggregate: false
        )
    }

    private func makeSiteItem(from site: HistorySiteRecord) -> HistoryListItem {
        HistoryListItem(
            id: "site:\(site.domain)",
            visitID: nil,
            url: site.url,
            title: site.title,
            domain: site.domain,
            siteDomain: site.domain,
            visitedAt: nil,
            timeText: "",
            visitCount: site.visitCount,
            isSiteAggregate: true
        )
    }

}
