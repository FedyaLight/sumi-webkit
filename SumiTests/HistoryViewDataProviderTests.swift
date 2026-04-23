import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class HistoryViewDataProviderTests: XCTestCase {
    private let fixedReferenceDate = ISO8601DateFormatter().date(from: "2026-04-23T12:00:00Z")!

    func testVisibleVisitsAreDeduplicatedByURLPerDay() async throws {
        let harness = try makeHarness()

        try await harness.store.recordVisit(
            url: URL(string: "https://example.com/a")!,
            title: "A",
            visitedAt: date("2026-04-23T10:00:00Z"),
            profileId: harness.profileID
        )
        try await harness.store.recordVisit(
            url: URL(string: "https://example.com/a")!,
            title: "A later",
            visitedAt: date("2026-04-23T11:00:00Z"),
            profileId: harness.profileID
        )
        try await harness.store.recordVisit(
            url: URL(string: "https://example.com/a")!,
            title: "A yesterday",
            visitedAt: date("2026-04-22T09:00:00Z"),
            profileId: harness.profileID
        )
        try await harness.store.recordVisit(
            url: URL(string: "https://news.ycombinator.com")!,
            title: "HN",
            visitedAt: date("2026-04-23T08:00:00Z"),
            profileId: harness.profileID
        )

        await harness.provider.refreshData()

        let allBatch = await harness.provider.visitsBatch(
            for: .rangeFilter(.all),
            source: .user,
            limit: 20,
            offset: 0
        )
        let todayBatch = await harness.provider.visitsBatch(
            for: .rangeFilter(.today),
            source: .user,
            limit: 20,
            offset: 0
        )
        let yesterdayBatch = await harness.provider.visitsBatch(
            for: .rangeFilter(.yesterday),
            source: .user,
            limit: 20,
            offset: 0
        )

        XCTAssertEqual(allBatch.visits.count, 3)
        XCTAssertEqual(todayBatch.visits.count, 2)
        XCTAssertEqual(yesterdayBatch.visits.count, 1)
    }

    func testRecentVisitedItemsOnlyIncludeToday() async throws {
        let harness = try makeHarness()
        let today = fixedReferenceDate
        let yesterday = harness.calendar.date(byAdding: .day, value: -1, to: today)!

        try await harness.store.recordVisit(
            url: URL(string: "https://example.com")!,
            title: "Today",
            visitedAt: today,
            profileId: harness.profileID
        )
        try await harness.store.recordVisit(
            url: URL(string: "https://example.org")!,
            title: "Yesterday",
            visitedAt: yesterday,
            profileId: harness.profileID
        )

        await harness.provider.refreshData()

        let recent = harness.provider.recentVisitedItems(maxCount: 10)

        XCTAssertEqual(recent.count, 1)
        XCTAssertEqual(recent.first?.displayTitle, "Today")
    }

    func testDeleteByDomainFilterRemovesMatchingRawVisits() async throws {
        let harness = try makeHarness()

        try await harness.store.recordVisit(
            url: URL(string: "https://example.com")!,
            title: "Example",
            visitedAt: date("2026-04-23T10:00:00Z"),
            profileId: harness.profileID
        )
        try await harness.store.recordVisit(
            url: URL(string: "https://www.example.com/docs")!,
            title: "Docs",
            visitedAt: date("2026-04-22T10:00:00Z"),
            profileId: harness.profileID
        )
        try await harness.store.recordVisit(
            url: URL(string: "https://other.com")!,
            title: "Other",
            visitedAt: date("2026-04-23T11:00:00Z"),
            profileId: harness.profileID
        )

        await harness.provider.refreshData()
        await harness.provider.deleteVisits(matching: .domainFilter(["example.com"]))

        let remaining = await harness.provider.visits(matching: .rangeFilter(.all))

        XCTAssertEqual(remaining.count, 1)
        XCTAssertEqual(remaining.first?.domain, "other.com")
    }

    private func makeHarness() throws -> (
        container: ModelContainer,
        store: HistoryStore,
        provider: HistoryViewDataProvider,
        profileID: UUID,
        calendar: Calendar
    ) {
        let container = try ModelContainer(
            for: Schema([HistoryEntryEntity.self, HistoryVisitEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = HistoryStore(container: container)
        let profileID = UUID()
        let calendar = makeUTCCalendar()
        let provider = HistoryViewDataProvider(
            store: store,
            currentProfileIdProvider: { profileID },
            referenceDateProvider: { self.fixedReferenceDate },
            calendar: calendar
        )
        return (container, store, provider, profileID, calendar)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func makeUTCCalendar() -> Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0) ?? .gmt
        return calendar
    }
}
