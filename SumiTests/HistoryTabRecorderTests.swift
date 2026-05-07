import Navigation
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class HistoryTabRecorderTests: XCTestCase {
    func testRegularCommitRecordsVisitAndBackForwardCommitDoesNot() async throws {
        let harness = try makeHarness()
        let firstURL = URL(string: "https://example.com/first")!
        let secondURL = URL(string: "https://example.com/second")!

        harness.tab.historyRecorder.didCommitMainFrameNavigation(
            to: firstURL,
            kind: .regular,
            tab: harness.tab
        )
        try await waitForVisitCount(1, harness: harness)

        harness.tab.historyRecorder.didCommitMainFrameNavigation(
            to: secondURL,
            kind: .backForward,
            tab: harness.tab
        )
        try await settleHistoryTasks()

        let visits = try await visits(in: harness.store, profileId: harness.profile.id)
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits.first?.url, firstURL)
    }

    func testSameDocumentAnchorAndPushRecordButReplaceAndPopDoNot() async throws {
        let harness = try makeHarness()
        let baseURL = URL(string: "https://example.com/page")!
        let anchorURL = URL(string: "https://example.com/page#section")!
        let pushURL = URL(string: "https://example.com/page?state=1")!
        let replaceURL = URL(string: "https://example.com/page?replace=1")!
        let popURL = URL(string: "https://example.com/page")!

        harness.tab.historyRecorder.didCommitMainFrameNavigation(
            to: baseURL,
            kind: .regular,
            tab: harness.tab
        )
        try await waitForVisitCount(1, harness: harness)

        harness.tab.historyRecorder.didSameDocumentNavigation(
            to: anchorURL,
            type: .anchorNavigation,
            tab: harness.tab
        )
        try await waitForVisitCount(2, harness: harness)

        harness.tab.historyRecorder.didSameDocumentNavigation(
            to: pushURL,
            type: .sessionStatePush,
            tab: harness.tab
        )
        try await waitForVisitCount(3, harness: harness)

        harness.tab.historyRecorder.didSameDocumentNavigation(
            to: replaceURL,
            type: .sessionStateReplace,
            tab: harness.tab
        )
        harness.tab.historyRecorder.didSameDocumentNavigation(
            to: popURL,
            type: .sessionStatePop,
            tab: harness.tab
        )
        try await settleHistoryTasks()

        let visits = try await visits(in: harness.store, profileId: harness.profile.id)
        XCTAssertEqual(visits.map(\.url), [pushURL, anchorURL, baseURL])
    }

    func testSameDocumentNavigationWithMissingTypeDoesNotRecordHistoryVisit() async throws {
        let harness = try makeHarness()
        let baseURL = URL(string: "https://example.com/page")!
        let unknownSameDocumentURL = URL(string: "https://example.com/page#unknown")!

        harness.tab.historyRecorder.didCommitMainFrameNavigation(
            to: baseURL,
            kind: .regular,
            tab: harness.tab
        )
        try await waitForVisitCount(1, harness: harness)

        harness.tab.historyRecorder.didSameDocumentNavigation(
            to: unknownSameDocumentURL,
            type: nil,
            tab: harness.tab
        )
        try await settleHistoryTasks()

        let visits = try await visits(in: harness.store, profileId: harness.profile.id)
        XCTAssertEqual(visits.map(\.url), [baseURL])
        XCTAssertEqual(harness.tab.historyRecorder.localVisitIDs.count, 1)
    }

    func testTitleUpdateMutatesExistingEntry() async throws {
        let harness = try makeHarness()
        let url = URL(string: "https://example.com/title")!

        harness.tab.historyRecorder.didCommitMainFrameNavigation(
            to: url,
            kind: .regular,
            tab: harness.tab
        )
        try await waitForVisitCount(1, harness: harness)

        harness.tab.historyRecorder.updateTitle("Resolved Title", tab: harness.tab)
        try await waitForTitle("Resolved Title", harness: harness)

        let visits = try await visits(in: harness.store, profileId: harness.profile.id)
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits.first?.title, "Resolved Title")
    }

    func testBurstNavigationHistoryWritesCoalesceUIRefresh() async throws {
        let harness = try makeHarness()
        try await settleHistoryTasks()

        let baselineRevision = harness.browserManager.historyManager.revision

        for index in 0..<3 {
            harness.tab.historyRecorder.didCommitMainFrameNavigation(
                to: URL(string: "https://example.com/burst-\(index)")!,
                kind: .regular,
                tab: harness.tab
            )
        }

        try await waitForVisitCount(3, harness: harness)
        try await waitUntil {
            harness.browserManager.historyManager.revision > baselineRevision
        }

        let refreshedRevision = harness.browserManager.historyManager.revision
        try await Task.sleep(nanoseconds: 300_000_000)
        XCTAssertEqual(harness.browserManager.historyManager.revision, refreshedRevision)
    }

    func testEphemeralAndNonHTTPURLsAreNotRecorded() async throws {
        let harness = try makeHarness()
        let ephemeralProfile = Profile.createEphemeral()
        let ephemeralTab = Tab(url: URL(string: "https://private.example.com")!)
        ephemeralTab.browserManager = harness.browserManager
        ephemeralTab.profileId = ephemeralProfile.id
        harness.browserManager.profileManager.profiles.append(ephemeralProfile)

        ephemeralTab.historyRecorder.didCommitMainFrameNavigation(
            to: URL(string: "https://private.example.com")!,
            kind: .regular,
            tab: ephemeralTab
        )
        harness.tab.historyRecorder.didCommitMainFrameNavigation(
            to: URL(string: "sumi://history?range=all")!,
            kind: .regular,
            tab: harness.tab
        )
        try await settleHistoryTasks()

        let regularVisits = try await visits(in: harness.store, profileId: harness.profile.id)
        let ephemeralVisits = try await visits(in: harness.store, profileId: ephemeralProfile.id)
        XCTAssertTrue(regularVisits.isEmpty)
        XCTAssertTrue(ephemeralVisits.isEmpty)
    }

    private func makeHarness() throws -> (
        container: ModelContainer,
        browserManager: BrowserManager,
        store: HistoryStore,
        profile: Profile,
        tab: Tab
    ) {
        let container = try ModelContainer(
            for: Schema([HistoryEntryEntity.self, HistoryVisitEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let browserManager = BrowserManager()
        let profile = Profile(name: "Primary")
        let historyManager = HistoryManager(context: context, profileId: profile.id)
        let tab = Tab(url: URL(string: "https://example.com")!, name: "Example")

        browserManager.modelContext = context
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.historyManager = historyManager
        tab.browserManager = browserManager
        tab.profileId = profile.id

        return (container, browserManager, historyManager.store, profile, tab)
    }

    private func waitForVisitCount(
        _ count: Int,
        harness: (
            container: ModelContainer,
            browserManager: BrowserManager,
            store: HistoryStore,
            profile: Profile,
            tab: Tab
        ),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await waitUntil(file: file, line: line) {
            let visits = try await visits(in: harness.store, profileId: harness.profile.id)
            return visits.count == count
        }
    }

    private func waitForTitle(
        _ title: String,
        harness: (
            container: ModelContainer,
            browserManager: BrowserManager,
            store: HistoryStore,
            profile: Profile,
            tab: Tab
        ),
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        try await waitUntil(file: file, line: line) {
            let visits = try await visits(in: harness.store, profileId: harness.profile.id)
            return visits.first?.title == title
        }
    }

    private func visits(
        in store: HistoryStore,
        profileId: UUID
    ) async throws -> [HistoryVisitRecord] {
        try await store.fetchVisitRecordsForExplicitAction(
            matching: .rangeFilter(.all),
            profileId: profileId,
            referenceDate: Date(),
            calendar: .autoupdatingCurrent
        )
    }

    private func waitUntil(
        timeoutNanoseconds: UInt64 = 1_000_000_000,
        file: StaticString = #filePath,
        line: UInt = #line,
        condition: () async throws -> Bool
    ) async throws {
        let deadline = Date().addingTimeInterval(TimeInterval(timeoutNanoseconds) / 1_000_000_000)
        while Date() < deadline {
            if try await condition() {
                return
            }
            try await Task.sleep(nanoseconds: 20_000_000)
        }
        XCTFail("Timed out waiting for history condition", file: file, line: line)
    }

    private func settleHistoryTasks() async throws {
        try await Task.sleep(nanoseconds: 120_000_000)
    }
}
