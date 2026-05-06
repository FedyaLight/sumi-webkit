import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class HistoryBoundedQueryTests: XCTestCase {
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-04-23T12:00:00Z")!

    func testRecentHistoryFetchRespectsLimit() async throws {
        let harness = try makeHarness()
        for index in 0..<6 {
            try await recordVisit(
                url: URL(string: "https://recent.example/\(index)")!,
                title: "Recent \(index)",
                at: referenceDate.addingTimeInterval(TimeInterval(index)),
                harness: harness
            )
        }

        let recent = try await harness.store.fetchRecentHistory(
            profileId: harness.profileID,
            limit: 3,
            referenceDate: referenceDate,
            calendar: harness.calendar
        )

        XCTAssertEqual(recent.count, 3)
        XCTAssertEqual(recent.map(\.title), ["Recent 5", "Recent 4", "Recent 3"])
    }

    func testHistorySearchRespectsLimitAndMatchingFields() async throws {
        let harness = try makeHarness()
        try await recordVisit(
            url: URL(string: "https://title.example/nope")!,
            title: "Needle Title",
            at: date("2026-04-23T11:00:00Z"),
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://url.example/needle")!,
            title: "URL Match",
            at: date("2026-04-23T10:00:00Z"),
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://needle-domain.example/path")!,
            title: "Domain Match",
            at: date("2026-04-23T09:00:00Z"),
            harness: harness
        )

        let matches = try await harness.store.searchHistory(
            query: "needle",
            profileId: harness.profileID,
            limit: 2,
            referenceDate: referenceDate,
            calendar: harness.calendar
        )

        XCTAssertEqual(matches.count, 2)
        XCTAssertEqual(matches.map(\.title), ["Needle Title", "URL Match"])
    }

    func testPaginatedHistoryFetchReturnsStableOrderedPagesWithoutDuplicates() async throws {
        let harness = try makeHarness()
        for index in 0..<5 {
            try await recordVisit(
                url: URL(string: "https://page.example/\(index)")!,
                title: "Page \(index)",
                at: referenceDate.addingTimeInterval(TimeInterval(index)),
                harness: harness
            )
        }

        let firstPage = try await harness.store.fetchHistoryPage(
            query: .rangeFilter(.all),
            profileId: harness.profileID,
            limit: 2,
            offset: 0,
            referenceDate: referenceDate,
            calendar: harness.calendar
        )
        let secondPage = try await harness.store.fetchHistoryPage(
            query: .rangeFilter(.all),
            profileId: harness.profileID,
            limit: 2,
            offset: firstPage.nextOffset,
            referenceDate: referenceDate,
            calendar: harness.calendar
        )

        XCTAssertEqual(firstPage.records.map(\.title), ["Page 4", "Page 3"])
        XCTAssertEqual(secondPage.records.map(\.title), ["Page 2", "Page 1"])
        XCTAssertTrue(firstPage.hasMore)
        XCTAssertTrue(secondPage.hasMore)
        XCTAssertTrue(Set(firstPage.records.map(\.id)).isDisjoint(with: Set(secondPage.records.map(\.id))))
    }

    func testLargeHistoryPageDoesNotReturnAllRowsAndOlderEntriesRemainReachable() async throws {
        let harness = try makeHarness()
        for index in 0..<150 {
            try await recordVisit(
                url: URL(string: "https://large.example/\(index)")!,
                title: "Large \(index)",
                at: referenceDate.addingTimeInterval(TimeInterval(index)),
                harness: harness
            )
        }

        let firstPage = try await harness.store.fetchHistoryPage(
            query: .rangeFilter(.all),
            profileId: harness.profileID,
            limit: 25,
            offset: 0,
            referenceDate: referenceDate,
            calendar: harness.calendar
        )
        let olderPage = try await harness.store.fetchHistoryPage(
            query: .rangeFilter(.all),
            profileId: harness.profileID,
            limit: 25,
            offset: 125,
            referenceDate: referenceDate,
            calendar: harness.calendar
        )

        XCTAssertEqual(firstPage.records.count, 25)
        XCTAssertTrue(firstPage.hasMore)
        XCTAssertEqual(olderPage.records.count, 25)
        XCTAssertEqual(olderPage.records.last?.title, "Large 0")
    }

    func testSitePagePaginationUsesDomainOrderAndCounts() async throws {
        let harness = try makeHarness()
        try await recordVisit(
            url: URL(string: "https://b.example/one")!,
            title: "B",
            at: date("2026-04-23T10:00:00Z"),
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://a.example/one")!,
            title: "A",
            at: date("2026-04-23T09:00:00Z"),
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://www.a.example/two")!,
            title: "A Two",
            at: date("2026-04-23T08:00:00Z"),
            harness: harness
        )

        let firstPage = try await harness.store.fetchSitePage(
            profileId: harness.profileID,
            searchTerm: nil,
            limit: 1,
            offset: 0
        )
        let secondPage = try await harness.store.fetchSitePage(
            profileId: harness.profileID,
            searchTerm: nil,
            limit: 1,
            offset: firstPage.nextOffset
        )

        XCTAssertEqual(firstPage.sites.map(\.domain), ["a.example"])
        XCTAssertEqual(firstPage.sites.first?.visitCount, 2)
        XCTAssertEqual(secondPage.sites.map(\.domain), ["b.example"])
    }

    func testClearAllRemainsExplicitAndSeparateFromBoundedPages() async throws {
        let harness = try makeHarness()
        for index in 0..<3 {
            try await recordVisit(
                url: URL(string: "https://clear.example/\(index)")!,
                title: "Clear \(index)",
                at: referenceDate.addingTimeInterval(TimeInterval(index)),
                harness: harness
            )
        }

        let page = try await harness.store.fetchHistoryPage(
            query: .rangeFilter(.all),
            profileId: harness.profileID,
            limit: 1,
            offset: 0,
            referenceDate: referenceDate,
            calendar: harness.calendar
        )
        XCTAssertEqual(page.records.count, 1)

        let deletedCount = try await harness.store.clearAllExplicit(profileId: harness.profileID)
        XCTAssertEqual(deletedCount, 3)
        let hasVisits = try await harness.store.hasVisits(profileId: harness.profileID)
        XCTAssertFalse(hasVisits)
    }

    func testProductionHistoryPathsDoNotUseUnboundedHistoryFetches() throws {
        let source = try productionSource(
            paths: [
                "Sumi/Managers/SearchManager/SearchManager.swift",
                "Sumi/History/HistoryPageViewModel.swift",
                "App/SumiCommands.swift",
                "App/SumiHistoryCommands.swift",
                "Sumi/Services/SumiBrowsingDataCleanupService.swift",
                "Sumi/Managers/History/HistoryManager.swift",
            ]
        )

        XCTAssertFalse(source.contains("store.visits("))
        XCTAssertFalse(source.contains("dataProvider.items(for:"))
        XCTAssertFalse(source.contains("visitRecords(matching:"))
        XCTAssertFalse(source.contains("rawVisits"))
        XCTAssertFalse(source.contains("DispatchSemaphore"))
        XCTAssertFalse(source.contains("DispatchGroup"))
        XCTAssertFalse(source.contains(".wait("))
    }

    private func makeHarness() throws -> (
        container: ModelContainer,
        store: HistoryStore,
        profileID: UUID,
        calendar: Calendar
    ) {
        let container = try ModelContainer(
            for: Schema([HistoryEntryEntity.self, HistoryVisitEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = HistoryStore(container: container)
        let profileID = UUID()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return (container, store, profileID, calendar)
    }

    private func recordVisit(
        url: URL,
        title: String,
        at timestamp: Date,
        harness: (
            container: ModelContainer,
            store: HistoryStore,
            profileID: UUID,
            calendar: Calendar
        )
    ) async throws {
        _ = try await harness.store.recordVisit(
            url: url,
            title: title,
            visitedAt: timestamp,
            profileId: harness.profileID
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func productionSource(paths: [String]) throws -> String {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        return try paths
            .map { try String(contentsOf: repoRoot.appendingPathComponent($0), encoding: .utf8) }
            .joined(separator: "\n")
    }
}
