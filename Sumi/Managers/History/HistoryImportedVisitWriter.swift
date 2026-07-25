//
//  HistoryImportedVisitWriter.swift
//  Sumi
//

import Foundation
import SwiftData

/// One visit recovered from another browser, ready to be written.
struct HistoryImportedVisit: Sendable {
    var url: URL
    var title: String
    var visitedAt: Date
}

/// Writes visits imported from another browser, and takes them back out again.
///
/// This is a peer of `HistoryVisitRecorder`, not an extension of it: the two
/// have different obligations. The recorder narrates one visit as it happens
/// and saves immediately; this writer lands tens of thousands at once, must
/// deduplicate against what is already there, and must be able to report
/// exactly what it inserted so an aborted import can be undone precisely.
struct HistoryImportedVisitWriter {
    let planner: HistoryEntityFetchPlanner

    /// What a single chunk actually changed, so compensation can be exact
    /// rather than approximate.
    struct Receipt: Codable, Equatable, Sendable {
        var insertedVisitIDs: [UUID] = []
        /// Entries this import brought into existence; pre-existing entries are
        /// never deleted on rollback, only decremented.
        var createdEntryIDs: [UUID] = []
        /// Prior `(numberOfTotalVisits, lastVisit)` for entries that already
        /// existed, keyed by entry id.
        var adjustedEntries: [UUID: PriorEntryState] = [:]

        struct PriorEntryState: Codable, Equatable, Sendable {
            var numberOfTotalVisits: Int
            var lastVisit: Date
        }

        mutating func merge(_ other: Receipt) {
            insertedVisitIDs.append(contentsOf: other.insertedVisitIDs)
            createdEntryIDs.append(contentsOf: other.createdEntryIDs)
            // Keep the earliest observation: it is the state to restore.
            adjustedEntries.merge(other.adjustedEntries) { first, _ in first }
        }
    }

    /// Inserts `visits`, skipping any that already exist at the same instant
    /// for the same URL. Re-running an import must not double the user's
    /// history.
    func insert(
        _ visits: [HistoryImportedVisit],
        profileId: UUID?,
        in ctx: ModelContext
    ) throws -> Receipt {
        var receipt = Receipt()

        for visit in visits {
            let domain = HistoryDomainResolver.normalizedDomain(for: visit.url)
            let displayTitle = visit.title.trimmingCharacters(in: .whitespacesAndNewlines)
            let existingEntry = try planner.existingEntry(
                for: visit.url,
                profileId: profileId,
                in: ctx
            )

            let entry: HistoryEntryEntity
            if let existingEntry {
                if receipt.adjustedEntries[existingEntry.id] == nil,
                   receipt.createdEntryIDs.contains(existingEntry.id) == false {
                    receipt.adjustedEntries[existingEntry.id] = Receipt.PriorEntryState(
                        numberOfTotalVisits: existingEntry.numberOfTotalVisits,
                        lastVisit: existingEntry.lastVisit
                    )
                }
                if try hasVisit(entryID: existingEntry.id, at: visit.visitedAt, in: ctx) {
                    continue
                }
                entry = existingEntry
            } else {
                entry = HistoryEntryEntity(
                    urlKey: HistoryEntityFetchPlanner.entryKey(for: visit.url, profileId: profileId),
                    urlString: visit.url.absoluteString,
                    title: displayTitle.isEmpty ? domain : displayTitle,
                    domain: domain,
                    siteDomain: HistoryDomainResolver.siteDomain(for: visit.url),
                    numberOfTotalVisits: 0,
                    lastVisit: visit.visitedAt,
                    profileId: profileId
                )
                ctx.insert(entry)
                receipt.createdEntryIDs.append(entry.id)
            }

            entry.numberOfTotalVisits += 1
            entry.lastVisit = max(entry.lastVisit, visit.visitedAt)
            // An imported visit belongs to no tab in this browser.
            let record = HistoryVisitEntity(
                id: UUID(),
                entryID: entry.id,
                visitedAt: visit.visitedAt,
                profileId: profileId,
                tabId: nil
            )
            ctx.insert(record)
            receipt.insertedVisitIDs.append(record.id)
        }

        try ctx.save()
        return receipt
    }

    /// Undoes exactly what `insert` did: deletes the visits it created, removes
    /// entries that would not have existed without it, and restores the
    /// counters of entries that were only nudged.
    func rollback(_ receipt: Receipt, in ctx: ModelContext) throws {
        let insertedIDs = Set(receipt.insertedVisitIDs)
        if insertedIDs.isEmpty == false {
            let visits = try ctx.fetch(FetchDescriptor<HistoryVisitEntity>())
            for visit in visits where insertedIDs.contains(visit.id) {
                ctx.delete(visit)
            }
        }

        let createdIDs = Set(receipt.createdEntryIDs)
        let entries = try ctx.fetch(FetchDescriptor<HistoryEntryEntity>())
        for entry in entries {
            if createdIDs.contains(entry.id) {
                ctx.delete(entry)
            } else if let prior = receipt.adjustedEntries[entry.id] {
                entry.numberOfTotalVisits = prior.numberOfTotalVisits
                entry.lastVisit = prior.lastVisit
            }
        }

        try ctx.save()
    }

    private func hasVisit(entryID: UUID, at date: Date, in ctx: ModelContext) throws -> Bool {
        var descriptor = FetchDescriptor<HistoryVisitEntity>(
            predicate: #Predicate { $0.entryID == entryID && $0.visitedAt == date }
        )
        descriptor.fetchLimit = 1
        return try ctx.fetch(descriptor).isEmpty == false
    }
}
