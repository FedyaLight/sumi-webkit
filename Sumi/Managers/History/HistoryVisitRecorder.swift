//
//  HistoryVisitRecorder.swift
//  Sumi
//

import Foundation
import SwiftData

/// Owns the history write path: recording visits, creating or reusing their
/// backing entries, and refreshing entry titles.
struct HistoryVisitRecorder {
    let planner: HistoryEntityFetchPlanner

    @discardableResult
    func recordVisit(
        in ctx: ModelContext,
        id: UUID,
        url: URL,
        title: String,
        visitedAt: Date,
        profileId: UUID?,
        tabId: UUID?
    ) throws -> UUID {
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

    func updateTitleIfNeeded(
        in ctx: ModelContext,
        title: String,
        url: URL,
        profileId: UUID?
    ) throws {
        let displayTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !displayTitle.isEmpty else { return }

        guard let entry = try planner.existingEntry(for: url, profileId: profileId, in: ctx),
              entry.title != displayTitle
        else {
            return
        }

        entry.title = displayTitle
        try ctx.save()
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
        if let existing = try planner.existingEntry(for: url, profileId: profileId, in: ctx) {
            return existing
        }

        let entry = HistoryEntryEntity(
            urlKey: HistoryEntityFetchPlanner.entryKey(for: url, profileId: profileId),
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
}
