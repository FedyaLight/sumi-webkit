//
//  HistoryVisitRecordReader.swift
//  Sumi
//

import Foundation
import SwiftData

/// Owns the visit read path: chunked scanning, visible-page assembly with
/// deduplication, query matching, and visit counting.
struct HistoryVisitRecordReader {
    let planner: HistoryEntityFetchPlanner

    func fetchHistoryPage(
        in ctx: ModelContext,
        query: HistoryQuery,
        profileId: UUID?,
        limit: Int,
        offset: Int,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> HistoryVisitPage {
        let query = query.normalizingDomainFilter
        guard limit > 0 else {
            return HistoryVisitPage(records: [], nextOffset: max(0, offset), hasMore: false)
        }

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
            let visits = try planner.fetchVisitChunk(
                in: ctx,
                profileId: profileId,
                dateRange: dateRange,
                limit: HistoryEntityFetchPlanner.scanChunkSize,
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

    func fetchVisitRecordsForExplicitAction(
        in ctx: ModelContext,
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> [HistoryVisitRecord] {
        let query = query.normalizingDomainFilter
        var rawOffset = 0
        var records: [HistoryVisitRecord] = []
        let dateRange = HistoryStoreRecordAssembly.dateRange(
            for: query,
            referenceDate: referenceDate,
            calendar: calendar
        )

        while true {
            let visits = try planner.fetchVisitChunk(
                in: ctx,
                profileId: profileId,
                dateRange: dateRange,
                limit: HistoryEntityFetchPlanner.scanChunkSize,
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

    func countVisits(
        in ctx: ModelContext,
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Int {
        let query = query.normalizingDomainFilter
        switch query {
        case .rangeFilter, .dateFilter, .timeRange:
            let descriptor = planner.visitDescriptor(
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
                in: ctx,
                matching: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: calendar
            ).count
        }
    }

    func hasVisits(in ctx: ModelContext, profileId: UUID?) throws -> Bool {
        var descriptor = planner.visitDescriptor(
            profileId: profileId,
            dateRange: nil,
            sortByDateDescending: false
        )
        descriptor.fetchLimit = 1
        return try !ctx.fetch(descriptor).isEmpty
    }

    func visitRecords(
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
}
