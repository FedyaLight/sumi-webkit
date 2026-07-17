import Combine
import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class HistoryTabRecorderTests: XCTestCase {
    func testRegularCommitRecordsVisitAndBackForwardCommitDoesNot() async throws {
        let harness = try makeHarness()
        let firstURL = URL(string: "https://example.com/first")!
        let secondURL = URL(string: "https://example.com/second")!

        harness.tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
            to: firstURL,
            kind: .regular,
            tab: harness.tab
        )
        await harness.browserManager.historyManager.flushPendingChanges()

        harness.tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
            to: secondURL,
            kind: .backForward,
            tab: harness.tab
        )
        await harness.browserManager.historyManager.flushPendingChanges()

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

        harness.tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
            to: baseURL,
            kind: .regular,
            tab: harness.tab
        )
        await harness.browserManager.historyManager.flushPendingChanges()

        harness.tab.navigationRuntime.historyRecorder.didSameDocumentNavigation(
            to: anchorURL,
            type: .anchorNavigation,
            tab: harness.tab
        )
        await harness.browserManager.historyManager.flushPendingChanges()

        harness.tab.navigationRuntime.historyRecorder.didSameDocumentNavigation(
            to: pushURL,
            type: .sessionStatePush,
            tab: harness.tab
        )
        await harness.browserManager.historyManager.flushPendingChanges()

        harness.tab.navigationRuntime.historyRecorder.didSameDocumentNavigation(
            to: replaceURL,
            type: .sessionStateReplace,
            tab: harness.tab
        )
        harness.tab.navigationRuntime.historyRecorder.didSameDocumentNavigation(
            to: popURL,
            type: .sessionStatePop,
            tab: harness.tab
        )
        await harness.browserManager.historyManager.flushPendingChanges()

        let visits = try await visits(in: harness.store, profileId: harness.profile.id)
        XCTAssertEqual(visits.map(\.url), [pushURL, anchorURL, baseURL])
    }

    func testSameDocumentNavigationWithMissingTypeDoesNotRecordHistoryVisit() async throws {
        let harness = try makeHarness()
        let baseURL = URL(string: "https://example.com/page")!
        let unknownSameDocumentURL = URL(string: "https://example.com/page#unknown")!

        harness.tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
            to: baseURL,
            kind: .regular,
            tab: harness.tab
        )
        await harness.browserManager.historyManager.flushPendingChanges()

        harness.tab.navigationRuntime.historyRecorder.didSameDocumentNavigation(
            to: unknownSameDocumentURL,
            type: nil,
            tab: harness.tab
        )
        await harness.browserManager.historyManager.flushPendingChanges()

        let visits = try await visits(in: harness.store, profileId: harness.profile.id)
        XCTAssertEqual(visits.map(\.url), [baseURL])
        XCTAssertEqual(harness.tab.navigationRuntime.historyRecorder.localVisitIDs.count, 1)
    }

    func testTitleUpdateMutatesExistingEntry() async throws {
        let harness = try makeHarness()
        let url = URL(string: "https://example.com/title")!

        harness.tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
            to: url,
            kind: .regular,
            tab: harness.tab
        )
        await harness.browserManager.historyManager.flushPendingChanges()

        harness.tab.navigationRuntime.historyRecorder.updateTitle("Resolved Title", tab: harness.tab)
        await harness.browserManager.historyManager.flushPendingChanges()

        let visits = try await visits(in: harness.store, profileId: harness.profile.id)
        XCTAssertEqual(visits.count, 1)
        XCTAssertEqual(visits.first?.title, "Resolved Title")
    }

    func testBurstNavigationHistoryWritesCoalesceUIRefresh() async throws {
        let harness = try makeHarness()
        let baselineRevision = harness.browserManager.historyManager.revision

        for index in 0..<3 {
            harness.tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
                to: URL(string: "https://example.com/burst-\(index)")!,
                kind: .regular,
                tab: harness.tab
            )
        }

        await harness.browserManager.historyManager.flushPendingChanges()
        XCTAssertEqual(harness.delayedActions.pendingActionCount, 1)
        let refresh = expectation(description: "coalesced history summary refresh")
        let revisionObservation = harness.browserManager.historyManager.$revision
            .dropFirst()
            .first()
            .sink { _ in refresh.fulfill() }

        harness.delayedActions.runAll()
        await fulfillment(of: [refresh], timeout: 1)

        XCTAssertEqual(harness.browserManager.historyManager.revision, baselineRevision + 1)
        withExtendedLifetime(revisionObservation) { /* Retain through the revision assertion. */ }
    }

    func testEphemeralAndNonHTTPURLsAreNotRecorded() async throws {
        let harness = try makeHarness()
        let ephemeralProfile = Profile.createEphemeral()
        let ephemeralTab = harness.browserManager.tabFactory.makeTab(
            url: URL(string: "https://private.example.com")!
        )
        ephemeralTab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: harness.browserManager))
        ephemeralTab.profileId = ephemeralProfile.id
        harness.browserManager.profileManager.profiles.append(ephemeralProfile)

        ephemeralTab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
            to: URL(string: "https://private.example.com")!,
            kind: .regular,
            tab: ephemeralTab
        )
        harness.tab.navigationRuntime.historyRecorder.didCommitMainFrameNavigation(
            to: URL(string: "sumi://history?range=all")!,
            kind: .regular,
            tab: harness.tab
        )
        await harness.browserManager.historyManager.flushPendingChanges()

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
        tab: Tab,
        delayedActions: ManualMainActorDelayedActionScheduler
    ) {
        let container = try ModelContainer(
            for: Schema([HistoryEntryEntity.self, HistoryVisitEntity.self]),
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let browserManager = BrowserManager(
            notificationService: FakeSumiNotificationService()
        )
        let delayedActions = ManualMainActorDelayedActionScheduler()
        let profile = Profile(name: "Primary")
        let historyManager = HistoryManager(
            context: context,
            profileId: profile.id,
            faviconCleaner: TabDependencyIsolationDefaults.historyFaviconCleaner,
            visitedLinkStore: TabDependencyIsolationDefaults.historyVisitedLinkStore,
            delayedActions: delayedActions.scheduler
        )
        let tab = browserManager.tabFactory.makeTab(
            url: URL(string: "https://example.com")!,
            name: "Example"
        )

        browserManager.modelContext = context
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.historyManager = historyManager
        tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
        tab.profileId = profile.id

        return (container, browserManager, historyManager.store, profile, tab, delayedActions)
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
}
