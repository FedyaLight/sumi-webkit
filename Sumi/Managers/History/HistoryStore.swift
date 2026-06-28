//
//  HistoryStore.swift
//  Sumi
//

import Foundation
import SwiftData

actor HistoryStore {
    static let defaultHistoryPageLimit = 100
    static let defaultSuggestionLimit = 20
    static let defaultRecentMenuLimit = 12

    private static let scanChunkSize = 256
    private static let siteChunkSize = 512

    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
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
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        let domain = HistoryDomainResolver.normalizedDomain(for: url)
        let siteDomain = HistoryDomainResolver.siteDomain(for: url)
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        let entry = try entry(
            for: url,
            in: ctx,
            title: displayTitle.isEmpty ? domain : displayTitle,
            domain: domain,
            siteDomain: siteDomain,
            visitedAt: visitedAt,
            profileId: profileId
        )

        if !displayTitle.isEmpty, entry.title != displayTitle {
            entry.title = displayTitle
        }
        entry.lastVisit = max(entry.lastVisit, visitedAt)
        entry.numberOfTotalVisits += 1

        let visit = HistoryVisitEntity(
            id: id,
            entryID: entry.id,
            visitedAt: visitedAt,
            profileId: profileId,
            tabId: tabId
        )
        ctx.insert(visit)
        try ctx.save()
        return id
    }

    func fetchRecentHistory(
        profileId: UUID?,
        limit: Int,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> [HistoryVisitRecord] {
        guard limit > 0 else { return [] }
        let page = try fetchHistoryPage(
            query: .rangeFilter(.today),
            profileId: profileId,
            limit: limit,
            offset: 0,
            referenceDate: referenceDate,
            calendar: calendar
        )
        return page.records
    }

    func fetchVisitedURLs(profileId: UUID?) throws -> [URL] {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        var rawOffset = 0
        var urls: [URL] = []
        while true {
            let entries = try fetchEntryChunk(
                in: ctx,
                profileId: profileId,
                limit: Self.siteChunkSize,
                offset: rawOffset
            )
            guard !entries.isEmpty else { break }
            rawOffset += entries.count
            urls.append(contentsOf: entries.compactMap { URL(string: $0.urlString) })
        }
        return urls
    }

    func searchHistory(
        query: String,
        profileId: UUID?,
        limit: Int,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> [HistoryVisitRecord] {
        guard limit > 0 else { return [] }
        return try fetchHistoryPage(
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
            return HistoryVisitPage(records: [], nextOffset: max(0, offset), hasMore: false)
        }

        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        var rawOffset = 0
        var visibleOffset = 0
        var pageRecords: [HistoryVisitRecord] = []
        var seenVisibleKeys = Set<String>()
        let startOffset = max(0, offset)
        let dateRange = HistoryStoreRecordAssembly.dateRange(
            for: query,
            referenceDate: referenceDate,
            calendar: calendar
        )

        while true {
            let visits = try fetchVisitChunk(
                in: ctx,
                profileId: profileId,
                dateRange: dateRange,
                limit: Self.scanChunkSize,
                offset: rawOffset
            )
            guard !visits.isEmpty else {
                return HistoryVisitPage(
                    records: pageRecords,
                    nextOffset: startOffset + pageRecords.count,
                    hasMore: false
                )
            }

            rawOffset += visits.count
            let records = try visitRecords(for: visits, in: ctx)

            for record in records where HistoryStoreRecordAssembly.visit(
                record,
                matches: query,
                referenceDate: referenceDate,
                calendar: calendar
            ) {
                let key = HistoryStoreRecordAssembly.visibleKey(for: record, calendar: calendar)
                guard seenVisibleKeys.insert(key).inserted else { continue }

                guard visibleOffset >= startOffset else {
                    visibleOffset += 1
                    continue
                }

                if pageRecords.count < limit {
                    pageRecords.append(record)
                    visibleOffset += 1
                } else {
                    return HistoryVisitPage(
                        records: pageRecords,
                        nextOffset: startOffset + pageRecords.count,
                        hasMore: true
                    )
                }
            }
        }
    }

    func fetchSitePage(
        profileId: UUID?,
        searchTerm: String?,
        limit: Int,
        offset: Int
    ) throws -> HistorySitePage {
        guard limit > 0 else {
            return HistorySitePage(sites: [], nextOffset: max(0, offset), hasMore: false)
        }

        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let query = searchTerm.map(SearchTextQuery.init)
        let startOffset = max(0, offset)
        let page = try fetchPagedSiteRecords(
            in: ctx,
            profileId: profileId,
            query: query,
            limit: limit,
            offset: startOffset
        )
        return HistorySitePage(
            sites: Array(page.prefix(limit)),
            nextOffset: startOffset + min(page.count, limit),
            hasMore: page.count > limit
        )
    }

    func fetchTopSites(
        profileId: UUID?,
        limit: Int
    ) throws -> [HistorySiteRecord] {
        guard limit > 0 else { return [] }

        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        return Array(
            try allSiteRecords(in: ctx, profileId: profileId)
                .values
                .sorted {
                    if $0.visitCount != $1.visitCount {
                        return $0.visitCount > $1.visitCount
                    }
                    return $0.domain.localizedStandardCompare($1.domain) == .orderedAscending
                }
                .prefix(limit)
        )
    }

    func hasVisits(profileId: UUID?) throws -> Bool {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        var descriptor = visitDescriptor(
            profileId: profileId,
            dateRange: nil,
            sortByDateDescending: false
        )
        descriptor.fetchLimit = 1
        return try !ctx.fetch(descriptor).isEmpty
    }

    func countVisits(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Int {
        switch query {
        case .rangeFilter, .dateFilter, .timeRange:
            let ctx = ModelContext(container)
            ctx.autosaveEnabled = false
            let descriptor = visitDescriptor(
                profileId: profileId,
                dateRange: HistoryStoreRecordAssembly.dateRange(
                    for: query,
                    referenceDate: referenceDate,
                    calendar: calendar
                ),
                sortByDateDescending: false
            )
            return try ctx.fetchCount(descriptor)
        case .searchTerm, .domainFilter, .visits:
            return try fetchVisitRecordsForExplicitAction(
                matching: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: calendar
            ).count
        }
    }

    func domains(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Set<String> {
        if case .domainFilter(let domains) = query {
            return domains
        }

        let records = try fetchVisitRecordsForExplicitAction(
            matching: query,
            profileId: profileId,
            referenceDate: referenceDate,
            calendar: calendar
        )
        return Set(records.map { $0.siteDomain ?? $0.domain })
    }

    func remainingHistoryHosts(
        forSiteDomains siteDomains: Set<String>,
        profileId: UUID?
    ) throws -> Set<String> {
        guard !siteDomains.isEmpty else { return [] }
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        var rawOffset = 0
        var hosts = Set<String>()

        while true {
            let entries = try fetchEntryChunk(
                in: ctx,
                profileId: profileId,
                limit: Self.siteChunkSize,
                offset: rawOffset
            )
            guard !entries.isEmpty else { break }
            rawOffset += entries.count

            for entry in entries where siteDomains.contains(entry.siteDomain ?? entry.domain) {
                if let host = URL(string: entry.urlString)?.host {
                    hosts.insert(host)
                }
            }
        }

        return hosts
    }

    func fetchVisitRecordsForExplicitAction(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> [HistoryVisitRecord] {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        var rawOffset = 0
        var records: [HistoryVisitRecord] = []
        let dateRange = HistoryStoreRecordAssembly.dateRange(
            for: query,
            referenceDate: referenceDate,
            calendar: calendar
        )

        while true {
            let visits = try fetchVisitChunk(
                in: ctx,
                profileId: profileId,
                dateRange: dateRange,
                limit: Self.scanChunkSize,
                offset: rawOffset
            )
            guard !visits.isEmpty else { break }
            rawOffset += visits.count
            records.append(contentsOf: try visitRecords(for: visits, in: ctx).filter {
                HistoryStoreRecordAssembly.visit(
                    $0,
                    matches: query,
                    referenceDate: referenceDate,
                    calendar: calendar
                )
            })
        }

        return records
    }

    func updateTitleIfNeeded(
        title: String,
        url: URL,
        profileId: UUID?
    ) throws {
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayTitle.isEmpty else { return }

        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        guard let entry = try existingEntry(for: url, profileId: profileId, in: ctx),
              entry.title != displayTitle
        else {
            return
        }

        entry.title = displayTitle
        try ctx.save()
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
            let ids = try matchingVisitIDs(
                for: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: calendar
            )
            return try deleteVisits(withIDs: ids, profileId: profileId)
        }
    }

    @discardableResult
    func deleteVisits(
        withIDs ids: Set<UUID>,
        profileId: UUID?
    ) throws -> Int {
        guard !ids.isEmpty else { return 0 }

        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let entities = try entitiesForDeletion(in: ctx, ids: ids, profileId: profileId)
        let affectedEntryIDs = Set(entities.map(\.entryID))
        entities.forEach(ctx.delete)
        try repairEntries(withIDs: affectedEntryIDs, in: ctx)
        try ctx.save()
        return entities.count
    }

    @discardableResult
    func clearAllExplicit(profileId: UUID?) throws -> Int {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        let entries = try fetchAllEntriesForExplicitClear(in: ctx, profileId: profileId)
        let visits = try fetchAllVisitsForExplicitClear(in: ctx, profileId: profileId)

        visits.forEach(ctx.delete)
        entries.forEach(ctx.delete)
        try ctx.save()
        return visits.count
    }

    private func matchingVisitIDs(
        for query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Set<UUID> {
        if case .visits(let identifiers) = query {
            return try exactVisitIDs(for: identifiers, profileId: profileId)
        }

        let records = try fetchVisitRecordsForExplicitAction(
            matching: query,
            profileId: profileId,
            referenceDate: referenceDate,
            calendar: calendar
        )
        return Set(records.map(\.id))
    }

    private func exactVisitIDs(
        for identifiers: [VisitIdentifier],
        profileId: UUID?
    ) throws -> Set<UUID> {
        guard !identifiers.isEmpty else { return [] }
        let uuidSet = Set(identifiers.compactMap { UUID(uuidString: $0.uuid) })
        guard !uuidSet.isEmpty else { return [] }

        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        let visits = try entitiesForDeletion(in: ctx, ids: uuidSet, profileId: profileId)
        let identifierSet = Set(identifiers)
        return Set(
            try visitRecords(for: visits, in: ctx)
                .filter { record in
                    identifierSet.contains(
                        VisitIdentifier(uuid: record.id.uuidString, url: record.url, date: record.visitedAt)
                    )
                }
                .map(\.id)
        )
    }

    private func entitiesForDeletion(
        in ctx: ModelContext,
        ids: Set<UUID>,
        profileId: UUID?
    ) throws -> [HistoryVisitEntity] {
        if let profileId {
            let predicate = #Predicate<HistoryVisitEntity> { entity in
                ids.contains(entity.id) && entity.profileId == profileId
            }
            return try ctx.fetch(FetchDescriptor(predicate: predicate))
        }

        let predicate = #Predicate<HistoryVisitEntity> { entity in
            ids.contains(entity.id)
        }
        return try ctx.fetch(FetchDescriptor(predicate: predicate))
    }

    private func fetchVisitChunk(
        in ctx: ModelContext,
        profileId: UUID?,
        dateRange: Range<Date>?,
        limit: Int,
        offset: Int
    ) throws -> [HistoryVisitEntity] {
        var descriptor = visitDescriptor(
            profileId: profileId,
            dateRange: dateRange,
            sortByDateDescending: true
        )
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return try ctx.fetch(descriptor)
    }

    private func visitDescriptor(
        profileId: UUID?,
        dateRange: Range<Date>?,
        sortByDateDescending: Bool
    ) -> FetchDescriptor<HistoryVisitEntity> {
        let sortDescriptors = sortByDateDescending
            ? [SortDescriptor(\HistoryVisitEntity.visitedAt, order: .reverse)]
            : []

        switch (profileId, dateRange) {
        case (.some(let profileId), .some(let dateRange)):
            let lowerBound = dateRange.lowerBound
            let upperBound = dateRange.upperBound
            let predicate = #Predicate<HistoryVisitEntity> { visit in
                visit.profileId == profileId
                    && visit.visitedAt >= lowerBound
                    && visit.visitedAt < upperBound
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
        case (.some(let profileId), .none):
            let predicate = #Predicate<HistoryVisitEntity> { visit in
                visit.profileId == profileId
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
        case (.none, .some(let dateRange)):
            let lowerBound = dateRange.lowerBound
            let upperBound = dateRange.upperBound
            let predicate = #Predicate<HistoryVisitEntity> { visit in
                visit.visitedAt >= lowerBound && visit.visitedAt < upperBound
            }
            return FetchDescriptor(predicate: predicate, sortBy: sortDescriptors)
        case (.none, .none):
            return FetchDescriptor(sortBy: sortDescriptors)
        }
    }

    private func visitRecords(
        for visits: [HistoryVisitEntity],
        in ctx: ModelContext
    ) throws -> [HistoryVisitRecord] {
        guard !visits.isEmpty else { return [] }
        let entryIDs = Set(visits.map(\.entryID))
        let predicate = #Predicate<HistoryEntryEntity> { entry in
            entryIDs.contains(entry.id)
        }
        let entries = try ctx.fetch(FetchDescriptor(predicate: predicate))
        return HistoryStoreRecordAssembly.visitRecords(
            for: visits.map(HistoryStoreRecordAssembly.VisitSnapshot.init),
            entries: entries.map(HistoryStoreRecordAssembly.EntrySnapshot.init)
        )
    }

    private func fetchEntryChunk(
        in ctx: ModelContext,
        profileId: UUID?,
        limit: Int,
        offset: Int
    ) throws -> [HistoryEntryEntity] {
        var descriptor: FetchDescriptor<HistoryEntryEntity>
        if let profileId {
            let predicate = #Predicate<HistoryEntryEntity> { entry in
                entry.profileId == profileId
            }
            descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\HistoryEntryEntity.domain)]
            )
        } else {
            descriptor = FetchDescriptor(sortBy: [SortDescriptor(\HistoryEntryEntity.domain)])
        }
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return try ctx.fetch(descriptor)
    }

    private func fetchSiteEntryChunk(
        in ctx: ModelContext,
        profileId: UUID?,
        source: HistoryStoreRecordAssembly.SiteEntrySource,
        limit: Int,
        offset: Int
    ) throws -> [HistoryEntryEntity] {
        var descriptor: FetchDescriptor<HistoryEntryEntity>
        switch (profileId, source) {
        case (.some(let profileId), .resolvedSiteDomain):
            let predicate = #Predicate<HistoryEntryEntity> { entry in
                entry.profileId == profileId && entry.siteDomain != nil
            }
            descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\HistoryEntryEntity.siteDomain),
                    SortDescriptor(\HistoryEntryEntity.domain),
                ]
            )
        case (.some(let profileId), .missingSiteDomain):
            let predicate = #Predicate<HistoryEntryEntity> { entry in
                entry.profileId == profileId && entry.siteDomain == nil
            }
            descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\HistoryEntryEntity.domain)]
            )
        case (.none, .resolvedSiteDomain):
            let predicate = #Predicate<HistoryEntryEntity> { entry in
                entry.siteDomain != nil
            }
            descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [
                    SortDescriptor(\HistoryEntryEntity.siteDomain),
                    SortDescriptor(\HistoryEntryEntity.domain),
                ]
            )
        case (.none, .missingSiteDomain):
            let predicate = #Predicate<HistoryEntryEntity> { entry in
                entry.siteDomain == nil
            }
            descriptor = FetchDescriptor(
                predicate: predicate,
                sortBy: [SortDescriptor(\HistoryEntryEntity.domain)]
            )
        }
        descriptor.fetchLimit = limit
        descriptor.fetchOffset = offset
        return try ctx.fetch(descriptor)
    }

    private func fetchPagedSiteRecords(
        in ctx: ModelContext,
        profileId: UUID?,
        query: SearchTextQuery?,
        limit: Int,
        offset: Int
    ) throws -> [HistorySiteRecord] {
        var resolvedCursor = HistoryStoreRecordAssembly.SiteGroupCursor(source: .resolvedSiteDomain)
        var missingCursor = HistoryStoreRecordAssembly.SiteGroupCursor(source: .missingSiteDomain)
        var resolvedGroup = try nextSiteGroup(from: &resolvedCursor, in: ctx, profileId: profileId)
        var missingGroup = try nextSiteGroup(from: &missingCursor, in: ctx, profileId: profileId)
        var visibleOffset = 0
        var page: [HistorySiteRecord] = []

        while let domain = HistoryStoreRecordAssembly.nextSiteDomain(
            resolvedGroup: resolvedGroup,
            missingGroup: missingGroup
        ) {
            var accumulator: HistoryStoreRecordAssembly.SiteAccumulator?
            if let group = resolvedGroup, group.domain == domain {
                HistoryStoreRecordAssembly.merge(group.accumulator, into: &accumulator, domain: domain)
                resolvedGroup = try nextSiteGroup(from: &resolvedCursor, in: ctx, profileId: profileId)
            }
            if let group = missingGroup, group.domain == domain {
                HistoryStoreRecordAssembly.merge(group.accumulator, into: &accumulator, domain: domain)
                missingGroup = try nextSiteGroup(from: &missingCursor, in: ctx, profileId: profileId)
            }

            guard let accumulator,
                  let record = HistoryStoreRecordAssembly.siteRecord(domain: domain, accumulator: accumulator)
            else {
                continue
            }

            if let query, !query.isEmpty, !HistoryStoreRecordAssembly.siteMatches(record, query: query) {
                continue
            }

            guard visibleOffset >= offset else {
                visibleOffset += 1
                continue
            }

            page.append(record)
            if page.count > limit {
                return page
            }
        }

        return page
    }

    private func nextSiteGroup(
        from cursor: inout HistoryStoreRecordAssembly.SiteGroupCursor,
        in ctx: ModelContext,
        profileId: UUID?
    ) throws -> HistoryStoreRecordAssembly.SiteGroup? {
        guard let firstEntry = try nextSiteEntry(from: &cursor, in: ctx, profileId: profileId) else {
            return nil
        }

        let domain = HistoryStoreRecordAssembly.effectiveSiteDomain(for: firstEntry)
        var accumulator = HistoryStoreRecordAssembly.SiteAccumulator(
            bestEntry: firstEntry,
            visitCount: firstEntry.numberOfTotalVisits
        )

        while let entry = try nextSiteEntry(from: &cursor, in: ctx, profileId: profileId) {
            let entryDomain = HistoryStoreRecordAssembly.effectiveSiteDomain(for: entry)
            guard entryDomain == domain else {
                cursor.pendingEntry = entry
                break
            }

            accumulator.visitCount += entry.numberOfTotalVisits
            if HistoryStoreRecordAssembly.comparePreferredEntries(entry, accumulator.bestEntry, for: domain) {
                accumulator.bestEntry = entry
            }
        }

        return HistoryStoreRecordAssembly.SiteGroup(domain: domain, accumulator: accumulator)
    }

    private func nextSiteEntry(
        from cursor: inout HistoryStoreRecordAssembly.SiteGroupCursor,
        in ctx: ModelContext,
        profileId: UUID?
    ) throws -> HistoryStoreRecordAssembly.EntrySnapshot? {
        if let pendingEntry = cursor.pendingEntry {
            cursor.pendingEntry = nil
            return pendingEntry
        }

        while cursor.bufferedIndex >= cursor.bufferedEntries.count {
            let entries = try fetchSiteEntryChunk(
                in: ctx,
                profileId: profileId,
                source: cursor.source,
                limit: Self.siteChunkSize,
                offset: cursor.rawOffset
            )
            guard !entries.isEmpty else { return nil }
            cursor.rawOffset += entries.count
            cursor.bufferedEntries = entries.map(HistoryStoreRecordAssembly.EntrySnapshot.init)
            cursor.bufferedIndex = 0
        }

        let entry = cursor.bufferedEntries[cursor.bufferedIndex]
        cursor.bufferedIndex += 1
        return entry
    }

    private func allSiteRecords(
        in ctx: ModelContext,
        profileId: UUID?
    ) throws -> [String: HistorySiteRecord] {
        var rawOffset = 0
        var accumulators: [String: HistoryStoreRecordAssembly.SiteAccumulator] = [:]

        while true {
            let entries = try fetchEntryChunk(
                in: ctx,
                profileId: profileId,
                limit: Self.siteChunkSize,
                offset: rawOffset
            )
            guard !entries.isEmpty else { break }
            rawOffset += entries.count
            for entry in entries.map(HistoryStoreRecordAssembly.EntrySnapshot.init) {
                let domain = HistoryStoreRecordAssembly.effectiveSiteDomain(for: entry)
                if var accumulator = accumulators[domain] {
                    accumulator.visitCount += entry.numberOfTotalVisits
                    if HistoryStoreRecordAssembly.comparePreferredEntries(entry, accumulator.bestEntry, for: domain) {
                        accumulator.bestEntry = entry
                    }
                    accumulators[domain] = accumulator
                } else {
                    accumulators[domain] = HistoryStoreRecordAssembly.SiteAccumulator(
                        bestEntry: entry,
                        visitCount: entry.numberOfTotalVisits
                    )
                }
            }
        }

        var records: [String: HistorySiteRecord] = [:]
        for (domain, accumulator) in accumulators {
            records[domain] = HistoryStoreRecordAssembly.siteRecord(domain: domain, accumulator: accumulator)
        }

        return records
    }

    private func fetchAllEntriesForExplicitClear(
        in ctx: ModelContext,
        profileId: UUID?
    ) throws -> [HistoryEntryEntity] {
        if let profileId {
            let predicate = #Predicate<HistoryEntryEntity> { entity in
                entity.profileId == profileId
            }
            return try ctx.fetch(FetchDescriptor(predicate: predicate))
        }
        return try ctx.fetch(FetchDescriptor<HistoryEntryEntity>())
    }

    private func fetchAllVisitsForExplicitClear(
        in ctx: ModelContext,
        profileId: UUID?
    ) throws -> [HistoryVisitEntity] {
        if let profileId {
            let predicate = #Predicate<HistoryVisitEntity> { visit in
                visit.profileId == profileId
            }
            return try ctx.fetch(FetchDescriptor(predicate: predicate))
        }
        return try ctx.fetch(FetchDescriptor<HistoryVisitEntity>())
    }

    private func entry(
        for url: URL,
        in ctx: ModelContext,
        title: String,
        domain: String,
        siteDomain: String?,
        visitedAt: Date,
        profileId: UUID?
    ) throws -> HistoryEntryEntity {
        if let existing = try existingEntry(for: url, profileId: profileId, in: ctx) {
            return existing
        }

        let entry = HistoryEntryEntity(
            urlKey: Self.entryKey(for: url, profileId: profileId),
            urlString: url.absoluteString,
            title: title,
            domain: domain,
            siteDomain: siteDomain,
            numberOfTotalVisits: 0,
            lastVisit: visitedAt,
            profileId: profileId
        )
        ctx.insert(entry)
        return entry
    }

    private func existingEntry(
        for url: URL,
        profileId: UUID?,
        in ctx: ModelContext
    ) throws -> HistoryEntryEntity? {
        let key = Self.entryKey(for: url, profileId: profileId)
        let predicate = #Predicate<HistoryEntryEntity> { entry in
            entry.urlKey == key
        }
        var descriptor = FetchDescriptor<HistoryEntryEntity>(predicate: predicate)
        descriptor.fetchLimit = 1
        return try ctx.fetch(descriptor).first
    }

    private func repairEntries(
        withIDs entryIDs: Set<UUID>,
        in ctx: ModelContext
    ) throws {
        guard !entryIDs.isEmpty else { return }

        for entryID in entryIDs {
            let entryPredicate = #Predicate<HistoryEntryEntity> { entry in
                entry.id == entryID
            }
            var entryDescriptor = FetchDescriptor<HistoryEntryEntity>(predicate: entryPredicate)
            entryDescriptor.fetchLimit = 1
            guard let entry = try ctx.fetch(entryDescriptor).first else { continue }

            let visitPredicate = #Predicate<HistoryVisitEntity> { visit in
                visit.entryID == entryID
            }
            var newestDescriptor = FetchDescriptor(
                predicate: visitPredicate,
                sortBy: [SortDescriptor(\HistoryVisitEntity.visitedAt, order: .reverse)]
            )
            newestDescriptor.fetchLimit = 1

            guard let newestVisit = try ctx.fetch(newestDescriptor).first else {
                ctx.delete(entry)
                continue
            }

            entry.lastVisit = newestVisit.visitedAt
            entry.numberOfTotalVisits = try ctx.fetchCount(FetchDescriptor(predicate: visitPredicate))
        }
    }

    private static func entryKey(for url: URL, profileId: UUID?) -> String {
        let profileKey = profileId?.uuidString.lowercased() ?? "global"
        return "\(profileKey)|\(url.absoluteString)"
    }
}
