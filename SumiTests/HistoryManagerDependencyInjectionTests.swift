import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class HistoryManagerDependencyInjectionTests: XCTestCase {
    private let referenceDate = ISO8601DateFormatter().date(from: "2026-06-01T12:00:00Z")!

    func testDeletingDomainUsesInjectedFaviconCleanerAndVisitedLinkStore() async throws {
        let harness = try makeHarness()
        let remainingURL = try XCTUnwrap(URL(string: "https://keep.example/path"))

        try await recordVisit(
            url: try XCTUnwrap(URL(string: "https://drop.example/remove")),
            title: "Remove",
            at: referenceDate,
            profileID: harness.profileID,
            store: harness.store
        )
        try await recordVisit(
            url: remainingURL,
            title: "Keep",
            at: referenceDate.addingTimeInterval(1),
            profileID: harness.profileID,
            store: harness.store
        )
        try await recordVisit(
            url: try XCTUnwrap(URL(string: "https://drop.example/other-profile")),
            title: "Other Profile",
            at: referenceDate.addingTimeInterval(2),
            profileID: UUID(),
            store: harness.store
        )

        await harness.historyManager.delete(query: .domainFilter(["drop.example"]))
        let replaceCall = await waitForReplaceCall(in: harness.visitedLinkStore)

        XCTAssertEqual(harness.faviconCleaner.burnDomainCalls.count, 1)
        XCTAssertEqual(harness.faviconCleaner.burnDomainCalls.first?.domains, Set(["drop.example"]))
        XCTAssertEqual(harness.faviconCleaner.burnDomainCalls.first?.remainingHistoryHosts, Set<String>())
        XCTAssertEqual(replaceCall?.profileID, harness.profileID)
        XCTAssertEqual(Set(replaceCall?.urls ?? []), Set([remainingURL]))
    }

    func testClearAllUsesInjectedFaviconCleanerAndClearsVisitedLinksForProfile() async throws {
        let harness = try makeHarness()

        try await recordVisit(
            url: try XCTUnwrap(URL(string: "https://clear.example/one")),
            title: "One",
            at: referenceDate,
            profileID: harness.profileID,
            store: harness.store
        )
        try await recordVisit(
            url: try XCTUnwrap(URL(string: "https://clear.example/two")),
            title: "Two",
            at: referenceDate.addingTimeInterval(1),
            profileID: harness.profileID,
            store: harness.store
        )

        await harness.historyManager.clearAll()
        let replaceCall = await waitForReplaceCall(in: harness.visitedLinkStore)

        XCTAssertEqual(harness.faviconCleaner.burnAfterHistoryClearCallCount, 1)
        XCTAssertEqual(replaceCall?.profileID, harness.profileID)
        XCTAssertEqual(replaceCall?.urls, [])
    }

    private func makeHarness() throws -> (
        container: ModelContainer,
        store: HistoryStore,
        historyManager: HistoryManager,
        profileID: UUID,
        faviconCleaner: FakeHistoryFaviconCleaner,
        visitedLinkStore: FakeHistoryVisitedLinkStore
    ) {
        let container = try ModelContainer(
            for: Schema([HistoryEntryEntity.self, HistoryVisitEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let store = HistoryStore(container: container)
        let profileID = UUID()
        let faviconCleaner = FakeHistoryFaviconCleaner()
        let visitedLinkStore = FakeHistoryVisitedLinkStore()
        let historyManager = HistoryManager(
            context: ModelContext(container),
            profileId: profileID,
            dependencies: HistoryManager.Dependencies(
                faviconCleaner: faviconCleaner,
                visitedLinkStore: visitedLinkStore
            )
        )

        return (
            container,
            store,
            historyManager,
            profileID,
            faviconCleaner,
            visitedLinkStore
        )
    }

    private func recordVisit(
        url: URL,
        title: String,
        at timestamp: Date,
        profileID: UUID,
        store: HistoryStore
    ) async throws {
        _ = try await store.recordVisit(
            url: url,
            title: title,
            visitedAt: timestamp,
            profileId: profileID
        )
    }

    private func waitForReplaceCall(
        in visitedLinkStore: FakeHistoryVisitedLinkStore,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async -> FakeHistoryVisitedLinkStore.ReplaceCall? {
        for _ in 0..<20 {
            if let call = visitedLinkStore.replaceCalls.last {
                return call
            }
            await Task.yield()
        }

        XCTFail("Timed out waiting for injected visited-link replacement", file: file, line: line)
        return nil
    }
}

@MainActor
private final class FakeHistoryFaviconCleaner: HistoryFaviconCleaning {
    struct BurnDomainCall: Equatable {
        let domains: Set<String>
        let remainingHistoryHosts: Set<String>
    }

    private(set) var burnAfterHistoryClearCallCount = 0
    private(set) var burnDomainCalls: [BurnDomainCall] = []

    func burnAfterHistoryClear(savedLogins: Set<String>) async {
        _ = savedLogins
        burnAfterHistoryClearCallCount += 1
    }

    func burnDomains(
        _ domains: Set<String>,
        remainingHistoryHosts: Set<String>,
        savedLogins: Set<String>
    ) async {
        _ = savedLogins
        burnDomainCalls.append(
            BurnDomainCall(
                domains: domains,
                remainingHistoryHosts: remainingHistoryHosts
            )
        )
    }
}

@MainActor
private final class FakeHistoryVisitedLinkStore: HistoryVisitedLinkStoring {
    struct ReplaceCall: Equatable {
        let urls: [URL]
        let profileID: UUID
    }

    private(set) var preloadCalls: [ReplaceCall] = []
    private(set) var replaceCalls: [ReplaceCall] = []

    func preloadVisitedLinks(_ urls: [URL], for profileId: UUID) {
        preloadCalls.append(ReplaceCall(urls: urls, profileID: profileId))
    }

    func replaceVisitedLinks(_ urls: [URL], for profileId: UUID) {
        replaceCalls.append(ReplaceCall(urls: urls, profileID: profileId))
    }
}
