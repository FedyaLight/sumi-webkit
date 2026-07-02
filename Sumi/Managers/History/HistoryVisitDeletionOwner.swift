//
//  HistoryVisitDeletionOwner.swift
//  Sumi
//

import Foundation
import SwiftData

/// Owns history deletion: resolving which visits a query targets, deleting
/// them, clearing all history, and repairing entry aggregates afterwards.
struct HistoryVisitDeletionOwner {
    let planner: HistoryEntityFetchPlanner
    let visitReader: HistoryVisitRecordReader

    @discardableResult
    func deleteVisits(
        in ctx: ModelContext,
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Int {
        switch query {
        case .rangeFilter(.all), .rangeFilter(.allSites):
            return try clearAllExplicit(in: ctx, profileId: profileId)
        default:
            let ids = try matchingVisitIDs(
                in: ctx,
                for: query,
                profileId: profileId,
                referenceDate: referenceDate,
                calendar: calendar
            )
            return try deleteVisits(in: ctx, withIDs: ids, profileId: profileId)
        }
    }

    @discardableResult
    func deleteVisits(
        in ctx: ModelContext,
        withIDs ids: Set<UUID>,
        profileId: UUID?
    ) throws -> Int {
        guard !ids.isEmpty else { return 0 }

        let entities = try planner.entitiesForDeletion(in: ctx, ids: ids, profileId: profileId)
        let affectedEntryIDs = Set(entities.map(\.entryID))
        entities.forEach(ctx.delete)
        try repairEntries(withIDs: affectedEntryIDs, in: ctx)
        try ctx.save()
        return entities.count
    }

    @discardableResult
    func clearAllExplicit(in ctx: ModelContext, profileId: UUID?) throws -> Int {
        let entries = try planner.fetchAllEntriesForExplicitClear(in: ctx, profileId: profileId)
        let visits = try planner.fetchAllVisitsForExplicitClear(in: ctx, profileId: profileId)

        visits.forEach(ctx.delete)
        entries.forEach(ctx.delete)
        try ctx.save()
        return visits.count
    }

    private func matchingVisitIDs(
        in ctx: ModelContext,
        for query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Set<UUID> {
        if case .visits(let identifiers) = query {
            return try exactVisitIDs(in: ctx, for: identifiers, profileId: profileId)
        }

        let records = try visitReader.fetchVisitRecordsForExplicitAction(
            in: ctx,
            matching: query,
            profileId: profileId,
            referenceDate: referenceDate,
            calendar: calendar
        )
        return Set(records.map(\.id))
    }

    private func exactVisitIDs(
        in ctx: ModelContext,
        for identifiers: [VisitIdentifier],
        profileId: UUID?
    ) throws -> Set<UUID> {
        guard !identifiers.isEmpty else { return [] }
        let uuidSet = Set(identifiers.compactMap { UUID(uuidString: $0.uuid) })
        guard !uuidSet.isEmpty else { return [] }

        let visits = try planner.entitiesForDeletion(in: ctx, ids: uuidSet, profileId: profileId)
        let identifierSet = Set(identifiers)
        return Set(
            try visitReader.visitRecords(for: visits, in: ctx)
                .filter { record in
                    identifierSet.contains(
                        VisitIdentifier(uuid: record.id.uuidString, url: record.url, date: record.visitedAt)
                    )
                }
                .map(\.id)
        )
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
}
