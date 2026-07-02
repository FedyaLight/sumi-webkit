//
//  HistorySiteRecordReader.swift
//  Sumi
//

import Foundation
import SwiftData

/// Owns the site-level read path: merging entry chunks into per-site
/// aggregates, streaming paged site records, and resolving site-scoped hosts
/// and URLs.
struct HistorySiteRecordReader {
    let planner: HistoryEntityFetchPlanner

    func fetchVisitedURLs(in ctx: ModelContext, profileId: UUID?) throws -> [URL] {
        var rawOffset = 0
        var urls: [URL] = []
        while true {
            let entries = try planner.fetchEntryChunk(
                in: ctx,
                profileId: profileId,
                limit: HistoryEntityFetchPlanner.siteChunkSize,
                offset: rawOffset
            )
            guard !entries.isEmpty else { break }
            rawOffset += entries.count
            urls.append(contentsOf: entries.compactMap { URL(string: $0.urlString) })
        }
        return urls
    }

    func fetchSitePage(
        in ctx: ModelContext,
        profileId: UUID?,
        searchTerm: String?,
        limit: Int,
        offset: Int
    ) throws -> HistorySitePage {
        guard limit > 0 else {
            return HistorySitePage(sites: [], nextOffset: max(0, offset), hasMore: false)
        }

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
        in ctx: ModelContext,
        profileId: UUID?,
        limit: Int
    ) throws -> [HistorySiteRecord] {
        guard limit > 0 else { return [] }
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

    func remainingHistoryHosts(
        in ctx: ModelContext,
        forSiteDomains siteDomains: Set<String>,
        profileId: UUID?
    ) throws -> Set<String> {
        let siteDomains = HistoryDomainResolver.siteDomains(for: siteDomains)
        guard !siteDomains.isEmpty else { return [] }
        var rawOffset = 0
        var hosts = Set<String>()

        while true {
            let entries = try planner.fetchEntryChunk(
                in: ctx,
                profileId: profileId,
                limit: HistoryEntityFetchPlanner.siteChunkSize,
                offset: rawOffset
            )
            guard !entries.isEmpty else { break }
            rawOffset += entries.count

            for entry in entries {
                let entrySiteDomain = entry.siteDomain
                    ?? HistoryDomainResolver.siteDomain(forDomain: entry.domain)
                    ?? entry.domain
                guard siteDomains.contains(entrySiteDomain) else { continue }
                if let url = URL(string: entry.urlString) {
                    let host = HistoryDomainResolver.normalizedDomain(for: url)
                    guard !host.isEmpty else { continue }
                    hosts.insert(host)
                }
            }
        }

        return hosts
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
            let entries = try planner.fetchSiteEntryChunk(
                in: ctx,
                profileId: profileId,
                source: cursor.source,
                limit: HistoryEntityFetchPlanner.siteChunkSize,
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
            let entries = try planner.fetchEntryChunk(
                in: ctx,
                profileId: profileId,
                limit: HistoryEntityFetchPlanner.siteChunkSize,
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
}
