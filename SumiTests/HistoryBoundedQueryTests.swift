import SwiftData
import WebKit
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
            url: URL(string: "https://beta.example.org/one")!,
            title: "B",
            at: date("2026-04-23T10:00:00Z"),
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://alpha.example.com/one")!,
            title: "A",
            at: date("2026-04-23T09:00:00Z"),
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://www.example.com/two")!,
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

        XCTAssertEqual(firstPage.sites.map(\.domain), ["example.com"])
        XCTAssertEqual(firstPage.sites.first?.visitCount, 2)
        XCTAssertEqual(secondPage.sites.map(\.domain), ["example.org"])
    }

    func testSitePagePaginationMergesLegacySiteDomainFallbacks() async throws {
        let harness = try makeHarness()
        let ctx = ModelContext(harness.container)
        ctx.autosaveEnabled = false
        insertEntry(
            urlString: "https://legacy.example/one",
            title: "Legacy One",
            domain: "legacy.example",
            siteDomain: nil,
            visitCount: 1,
            lastVisit: date("2026-04-23T09:00:00Z"),
            profileID: harness.profileID,
            in: ctx
        )
        insertEntry(
            urlString: "https://www.legacy.example/two",
            title: "Legacy Two",
            domain: "www.legacy.example",
            siteDomain: "legacy.example",
            visitCount: 2,
            lastVisit: date("2026-04-23T10:00:00Z"),
            profileID: harness.profileID,
            in: ctx
        )
        insertEntry(
            urlString: "https://aaa.example/other",
            title: "Other Profile",
            domain: "aaa.example",
            siteDomain: "aaa.example",
            visitCount: 5,
            lastVisit: date("2026-04-23T11:00:00Z"),
            profileID: UUID(),
            in: ctx
        )
        try ctx.save()

        let page = try await harness.store.fetchSitePage(
            profileId: harness.profileID,
            searchTerm: nil,
            limit: 10,
            offset: 0
        )

        XCTAssertEqual(page.sites.map(\.domain), ["legacy.example"])
        XCTAssertEqual(page.sites.first?.visitCount, 3)
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

    func testClearAllExplicitIsIdempotentWhenRepeated() async throws {
        let harness = try makeHarness()
        for index in 0..<2 {
            try await recordVisit(
                url: URL(string: "https://idempotent.example/\(index)")!,
                title: "Idempotent \(index)",
                at: referenceDate.addingTimeInterval(TimeInterval(index)),
                harness: harness
            )
        }

        let firstDeletedCount = try await harness.store.clearAllExplicit(profileId: harness.profileID)
        let secondDeletedCount = try await harness.store.clearAllExplicit(profileId: harness.profileID)
        let hasVisits = try await harness.store.hasVisits(profileId: harness.profileID)

        XCTAssertEqual(firstDeletedCount, 2)
        XCTAssertEqual(secondDeletedCount, 0)
        XCTAssertFalse(hasVisits)
    }

    func testHistoryDeleteReloadsVisitedLinksOnlyForCurrentProfile() async throws {
        let harness = try makeHarness()
        let historyManager = HistoryManager(
            context: ModelContext(harness.container),
            profileId: harness.profileID
        )
        let provider = SharedVisitedLinkStoreProvider.shared
        let currentStore = FakeVisitedLinkStore()
        let otherStore = FakeVisitedLinkStore()
        let otherProfileID = UUID()

        provider.seedStoreForTesting(currentStore, profileId: harness.profileID)
        provider.seedStoreForTesting(otherStore, profileId: otherProfileID)
        defer {
            provider.discardStore(for: harness.profileID)
            provider.discardStore(for: otherProfileID)
        }

        let remainingURL = URL(string: "https://keep.example/remaining")!
        try await recordVisit(
            url: URL(string: "https://drop.example/remove")!,
            title: "Remove",
            at: referenceDate.addingTimeInterval(1),
            harness: harness
        )
        try await recordVisit(
            url: remainingURL,
            title: "Keep",
            at: referenceDate.addingTimeInterval(2),
            harness: harness
        )
        try await harness.store.recordVisit(
            url: URL(string: "https://other.example/other")!,
            title: "Other",
            visitedAt: referenceDate.addingTimeInterval(3),
            profileId: otherProfileID
        )

        await historyManager.delete(
            query: .domainFilter(["drop.example"])
        )

        await waitForVisitedLinkReload(store: currentStore, expectedRemoveAllCount: 1)
        XCTAssertEqual(currentStore.removeAllCallCount, 1)
        XCTAssertEqual(currentStore.addedURLs, [remainingURL])
        XCTAssertEqual(otherStore.removeAllCallCount, 0)
        XCTAssertTrue(otherStore.addedURLs.isEmpty)
    }

    func testHistoryAndCleanupDomainConsumersShareSiteIdentity() async throws {
        let harness = try makeHarness()
        try await recordVisit(
            url: URL(string: "https://www.bbc.co.uk/news?utm=1#top")!,
            title: "BBC",
            at: date("2026-04-23T10:00:00Z"),
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://sport.bbc.co.uk/football?tab=live")!,
            title: "BBC Sport",
            at: date("2026-04-23T11:00:00Z"),
            harness: harness
        )

        let historyDomains = try await harness.store.domains(
            matching: .rangeFilter(.all),
            profileId: harness.profileID,
            referenceDate: referenceDate,
            calendar: harness.calendar
        )
        let domainInventory = SumiBrowsingDataDomainInventory(
            websiteDataCleanupService: FakeBrowsingDataCleanupService()
        )

        XCTAssertEqual(historyDomains, Set(["bbc.co.uk"]))
        XCTAssertEqual(
            domainInventory.normalizeDomains([" WWW.BBC.CO.UK. ", ".sport.bbc.co.uk"]),
            historyDomains
        )

        let deletedCount = try await harness.store.deleteVisits(
            matching: .domainFilter(["WWW.BBC.CO.UK."]),
            profileId: harness.profileID,
            referenceDate: referenceDate,
            calendar: harness.calendar
        )

        XCTAssertEqual(deletedCount, 2)
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

    private func insertEntry(
        urlString: String,
        title: String,
        domain: String,
        siteDomain: String?,
        visitCount: Int,
        lastVisit: Date,
        profileID: UUID,
        in ctx: ModelContext
    ) {
        ctx.insert(
            HistoryEntryEntity(
                urlKey: "\(profileID.uuidString.lowercased())|\(urlString)",
                urlString: urlString,
                title: title,
                domain: domain,
                siteDomain: siteDomain,
                numberOfTotalVisits: visitCount,
                lastVisit: lastVisit,
                profileId: profileID
            )
        )
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }

    private func waitForVisitedLinkReload(
        store: FakeVisitedLinkStore,
        expectedRemoveAllCount: Int,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async {
        for _ in 0..<20 {
            if store.removeAllCallCount >= expectedRemoveAllCount {
                return
            }
            await Task.yield()
        }
        XCTAssertEqual(
            store.removeAllCallCount,
            expectedRemoveAllCount,
            "Timed out waiting for visited-link reload",
            file: file,
            line: line
        )
    }
}

@objcMembers
private final class FakeVisitedLinkStore: NSObject {
    private(set) var removeAllCallCount = 0
    private(set) var addedURLs: [URL] = []

    func addVisitedLinkWithURL(_ url: NSURL) {
        addedURLs.append(url as URL)
    }

    func removeAll() {
        removeAllCallCount += 1
        addedURLs.removeAll()
    }
}

@MainActor
private final class FakeBrowsingDataCleanupService: SumiWebsiteDataCleanupServicing {
    func fetchCookies(in dataStore: WKWebsiteDataStore) async -> [HTTPCookie] {
        []
    }

    func fetchWebsiteDataRecords(
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [WKWebsiteDataRecord] {
        []
    }

    func fetchSiteDataEntries(
        forDomain domain: String,
        ofTypes dataTypes: Set<String>,
        in dataStore: WKWebsiteDataStore
    ) async -> [SumiSiteDataEntry] {
        []
    }

    func removeCookies(
        _ selection: SumiCookieRemovalSelection,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteData(
        ofTypes dataTypes: Set<String>,
        modifiedSince date: Date,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteDataForDomain(
        _ domain: String,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteDataForExactHost(
        _ host: String,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func removeWebsiteDataForDomains(
        _ domains: Set<String>,
        ofTypes dataTypes: Set<String>,
        includingCookies: Bool,
        in dataStore: WKWebsiteDataStore
    ) async {}

    func clearAllProfileWebsiteData(in dataStore: WKWebsiteDataStore) async {}

    func removePersistentDataStore(forIdentifier identifier: UUID) async -> Bool {
        true
    }

    func prunePersistentDataStores(keeping identifiersToKeep: Set<UUID>) async -> [UUID] {
        []
    }
}
