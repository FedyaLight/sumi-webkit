//
//  HistoryStore.swift
//  Sumi
//

import Foundation
import SwiftData

actor HistoryStore {
    private let container: ModelContainer

    init(container: ModelContainer) {
        self.container = container
    }

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

    func visits(profileId: UUID?) throws -> [HistoryVisitRecord] {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        let entries: [HistoryEntryEntity]
        if let profileId {
            let predicate = #Predicate<HistoryEntryEntity> { entity in
                entity.profileId == profileId
            }
            entries = try ctx.fetch(FetchDescriptor(predicate: predicate))
        } else {
            entries = try ctx.fetch(FetchDescriptor<HistoryEntryEntity>())
        }

        let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

        let visits: [HistoryVisitEntity]
        if let profileId {
            let predicate = #Predicate<HistoryVisitEntity> { visit in
                visit.profileId == profileId
            }
            var descriptor = FetchDescriptor<HistoryVisitEntity>(
                predicate: predicate,
                sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 20_000
            visits = try ctx.fetch(descriptor)
        } else {
            var descriptor = FetchDescriptor<HistoryVisitEntity>(
                sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
            )
            descriptor.fetchLimit = 20_000
            visits = try ctx.fetch(descriptor)
        }

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
    func clearAll(profileId: UUID?) throws -> Int {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false

        let entries: [HistoryEntryEntity]
        if let profileId {
            let predicate = #Predicate<HistoryEntryEntity> { entity in
                entity.profileId == profileId
            }
            entries = try ctx.fetch(FetchDescriptor(predicate: predicate))
        } else {
            entries = try ctx.fetch(FetchDescriptor<HistoryEntryEntity>())
        }

        let visits: [HistoryVisitEntity]
        if let profileId {
            let predicate = #Predicate<HistoryVisitEntity> { visit in
                visit.profileId == profileId
            }
            visits = try ctx.fetch(FetchDescriptor(predicate: predicate))
        } else {
            visits = try ctx.fetch(FetchDescriptor<HistoryVisitEntity>())
        }

        visits.forEach(ctx.delete)
        entries.forEach(ctx.delete)
        try ctx.save()
        return visits.count
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
            let visits = try ctx.fetch(FetchDescriptor(
                predicate: visitPredicate,
                sortBy: [SortDescriptor(\.visitedAt, order: .reverse)]
            ))

            guard let newestVisit = visits.first else {
                ctx.delete(entry)
                continue
            }

            entry.lastVisit = newestVisit.visitedAt
            entry.numberOfTotalVisits = visits.count
        }
    }

    private static func entryKey(for url: URL, profileId: UUID?) -> String {
        let profileKey = profileId?.uuidString.lowercased() ?? "global"
        return "\(profileKey)|\(url.absoluteString)"
    }
}
