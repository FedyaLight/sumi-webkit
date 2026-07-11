@testable import Sumi
import SumiDomain
import XCTest

@MainActor
final class FloatingBarBrowserContextFactoryTests: XCTestCase {
    func testHistoryDeletionQueryUsesVisitIDWhenAvailable() {
        let visitID = VisitIdentifier(
            uuid: "visit-1",
            url: URL(string: "https://example.com/page")!,
            date: Date(timeIntervalSince1970: 10)
        )
        let entry = makeHistoryEntry(
            visitID: visitID,
            domain: "example.com",
            siteDomain: "site.example.com"
        )

        XCTAssertEqual(
            FloatingBarBrowserContextFactory.historyDeletionQuery(for: entry),
            .visits([visitID])
        )
    }

    func testHistoryDeletionQueryUsesSiteDomainForAggregateEntry() {
        let entry = makeHistoryEntry(
            visitID: nil,
            domain: "sub.example.com",
            siteDomain: "example.com"
        )

        XCTAssertEqual(
            FloatingBarBrowserContextFactory.historyDeletionQuery(for: entry),
            .domainFilter(["example.com"])
        )
    }

    func testHistoryDeletionQueryFallsBackToEntryDomain() {
        let entry = makeHistoryEntry(
            visitID: nil,
            domain: "example.com",
            siteDomain: nil
        )

        XCTAssertEqual(
            FloatingBarBrowserContextFactory.historyDeletionQuery(for: entry),
            .domainFilter(["example.com"])
        )
    }

    private func makeHistoryEntry(
        visitID: VisitIdentifier?,
        domain: String,
        siteDomain: String?
    ) -> HistoryListItem {
        HistoryListItem(
            id: visitID?.description ?? domain,
            visitID: visitID,
            url: URL(string: "https://\(domain)/page")
                ?? SumiSurface.emptyTabURL,
            title: "Example",
            domain: domain,
            siteDomain: siteDomain,
            visitedAt: Date(timeIntervalSince1970: 20),
            timeText: "12:00",
            visitCount: 1,
            isSiteAggregate: visitID == nil
        )
    }
}
