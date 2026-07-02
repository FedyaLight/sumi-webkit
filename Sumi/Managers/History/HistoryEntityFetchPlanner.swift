//
//  HistoryEntityFetchPlanner.swift
//  Sumi
//

import Foundation
import SwiftData

/// Builds and executes the chunked SwiftData fetches shared by the history
/// read, write, and deletion owners. Owns predicate/sort construction so the
/// entity query shape stays in one place.
struct HistoryEntityFetchPlanner {
    static let scanChunkSize = 256
    static let siteChunkSize = 512

    func visitDescriptor(
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

    func fetchVisitChunk(
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

    func fetchEntryChunk(
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

    func fetchSiteEntryChunk(
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

    func entitiesForDeletion(
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

    func fetchAllEntriesForExplicitClear(
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

    func fetchAllVisitsForExplicitClear(
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

    func existingEntry(
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

    static func entryKey(for url: URL, profileId: UUID?) -> String {
        let profileKey = profileId?.uuidString.lowercased() ?? "global"
        return "\(profileKey)|\(url.absoluteString)"
    }
}
