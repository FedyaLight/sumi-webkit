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

    private let container: ModelContainer
    private let recorder: HistoryVisitRecorder
    private let importWriter: HistoryImportedVisitWriter
    private let visitReader: HistoryVisitRecordReader
    private let siteReader: HistorySiteRecordReader
    private let deletionOwner: HistoryVisitDeletionOwner

    init(container: ModelContainer) {
        self.container = container
        let planner = HistoryEntityFetchPlanner()
        let visitReader = HistoryVisitRecordReader(planner: planner)
        self.recorder = HistoryVisitRecorder(planner: planner)
        self.importWriter = HistoryImportedVisitWriter(planner: planner)
        self.visitReader = visitReader
        self.siteReader = HistorySiteRecordReader(planner: planner)
        self.deletionOwner = HistoryVisitDeletionOwner(
            planner: planner,
            visitReader: visitReader
        )
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
        try recorder.recordVisit(
            in: makeContext(),
            id: id,
            url: url,
            title: title,
            visitedAt: visitedAt,
            profileId: profileId,
            tabId: tabId
        )
    }

    /// Writes a chunk of visits imported from another browser and reports what
    /// it changed, so an aborted import can be undone exactly.
    func installImportedVisits(
        _ visits: [HistoryImportedVisit],
        profileId: UUID?
    ) throws -> HistoryImportedVisitWriter.Receipt {
        try importWriter.insert(visits, profileId: profileId, in: makeContext())
    }

    func rollbackImportedVisits(_ receipt: HistoryImportedVisitWriter.Receipt) throws {
        try importWriter.rollback(receipt, in: makeContext())
    }

    func updateTitleIfNeeded(
        title: String,
        url: URL,
        profileId: UUID?
    ) throws {
        try recorder.updateTitleIfNeeded(
            in: makeContext(),
            title: title,
            url: url,
            profileId: profileId
        )
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
        try visitReader.fetchHistoryPage(
            in: makeContext(),
            query: query,
            profileId: profileId,
            limit: limit,
            offset: offset,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func fetchVisitRecordsForExplicitAction(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> [HistoryVisitRecord] {
        try visitReader.fetchVisitRecordsForExplicitAction(
            in: makeContext(),
            matching: query,
            profileId: profileId,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func countVisits(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Int {
        try visitReader.countVisits(
            in: makeContext(),
            matching: query,
            profileId: profileId,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    func hasVisits(profileId: UUID?) throws -> Bool {
        try visitReader.hasVisits(in: makeContext(), profileId: profileId)
    }

    func domains(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Set<String> {
        if case .domainFilter(let domains) = query {
            return HistoryDomainResolver.siteDomains(for: domains)
        }

        let records = try fetchVisitRecordsForExplicitAction(
            matching: query,
            profileId: profileId,
            referenceDate: referenceDate,
            calendar: calendar
        )
        return Set(records.map { $0.siteDomain ?? $0.domain })
    }

    func fetchVisitedURLs(profileId: UUID?) throws -> [URL] {
        try siteReader.fetchVisitedURLs(in: makeContext(), profileId: profileId)
    }

    func fetchSitePage(
        profileId: UUID?,
        searchTerm: String?,
        limit: Int,
        offset: Int
    ) throws -> HistorySitePage {
        try siteReader.fetchSitePage(
            in: makeContext(),
            profileId: profileId,
            searchTerm: searchTerm,
            limit: limit,
            offset: offset
        )
    }

    func fetchTopSites(
        profileId: UUID?,
        limit: Int
    ) throws -> [HistorySiteRecord] {
        try siteReader.fetchTopSites(in: makeContext(), profileId: profileId, limit: limit)
    }

    func remainingHistoryHosts(
        forSiteDomains siteDomains: Set<String>,
        profileId: UUID?
    ) throws -> Set<String> {
        try siteReader.remainingHistoryHosts(
            in: makeContext(),
            forSiteDomains: siteDomains,
            profileId: profileId
        )
    }

    @discardableResult
    func deleteVisits(
        matching query: HistoryQuery,
        profileId: UUID?,
        referenceDate: Date,
        calendar: Calendar
    ) throws -> Int {
        try deletionOwner.deleteVisits(
            in: makeContext(),
            matching: query,
            profileId: profileId,
            referenceDate: referenceDate,
            calendar: calendar
        )
    }

    @discardableResult
    func deleteVisits(
        withIDs ids: Set<UUID>,
        profileId: UUID?
    ) throws -> Int {
        try deletionOwner.deleteVisits(in: makeContext(), withIDs: ids, profileId: profileId)
    }

    @discardableResult
    func clearAllExplicit(profileId: UUID?) throws -> Int {
        try deletionOwner.clearAllExplicit(in: makeContext(), profileId: profileId)
    }

    private func makeContext() -> ModelContext {
        let ctx = ModelContext(container)
        ctx.autosaveEnabled = false
        return ctx
    }
}
