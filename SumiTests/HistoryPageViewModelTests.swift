import SwiftData
import XCTest

@testable import Sumi

@MainActor
final class HistoryPageViewModelTests: XCTestCase {
    private let fixedReferenceDate = ISO8601DateFormatter().date(from: "2026-04-23T12:00:00Z")!

    func testHistoryTabUsesAllRangeByDefault() throws {
        let harness = try makeHarness()

        harness.browserManager.openHistoryTab(selecting: .older, in: harness.windowState)
        let viewModel = HistoryPageViewModel(browserManager: harness.browserManager, windowState: harness.windowState)

        XCTAssertEqual(viewModel.selectedRange, .all)
        XCTAssertFalse(harness.browserManager.currentTab(for: harness.windowState)?.requiresPrimaryWebView ?? true)
        XCTAssertEqual(
            harness.browserManager.currentTab(for: harness.windowState)?.url,
            SumiSurface.historySurfaceURL(rangeQuery: HistoryRange.all.paneQueryValue)
        )
    }

    func testOpeningRowFromHistoryTabReplacesSameTabAndLeavesNoHistoryTabs() throws {
        let harness = try makeHarness()
        let item = makeItem(url: URL(string: "https://example.com/article")!, title: "Article")

        harness.browserManager.openHistoryTab(in: harness.windowState)
        let historyTabID = try XCTUnwrap(harness.browserManager.currentTab(for: harness.windowState)?.id)
        let routingRevision = harness.windowState.nativeSurfaceRoutingRevision
        let viewModel = HistoryPageViewModel(browserManager: harness.browserManager, windowState: harness.windowState)

        viewModel.openFromRow(item, modifiers: [])

        let currentTab = try XCTUnwrap(harness.browserManager.currentTab(for: harness.windowState))
        XCTAssertEqual(currentTab.id, historyTabID)
        XCTAssertEqual(currentTab.url, item.url)
        XCTAssertFalse(currentTab.representsSumiHistorySurface)
        XCTAssertTrue(currentTab.requiresPrimaryWebView)
        XCTAssertEqual(harness.windowState.nativeSurfaceRoutingRevision, routingRevision + 1)
        XCTAssertEqual(
            harness.browserManager.tabManager.tabs(in: harness.space).filter(\.representsSumiHistorySurface).count,
            0
        )
    }

    func testCommandOpeningRowCreatesForegroundNewTab() throws {
        let harness = try makeHarness()
        let item = makeItem(url: URL(string: "https://example.com/new-tab")!, title: "New Tab")

        harness.browserManager.openHistoryTab(in: harness.windowState)
        let historyTabID = try XCTUnwrap(harness.browserManager.currentTab(for: harness.windowState)?.id)
        let routingRevision = harness.windowState.nativeSurfaceRoutingRevision
        let viewModel = HistoryPageViewModel(browserManager: harness.browserManager, windowState: harness.windowState)

        viewModel.openFromRow(item, modifiers: [.command])

        let currentTab = try XCTUnwrap(harness.browserManager.currentTab(for: harness.windowState))
        XCTAssertNotEqual(currentTab.id, historyTabID)
        XCTAssertEqual(currentTab.url, item.url)
        XCTAssertEqual(harness.windowState.nativeSurfaceRoutingRevision, routingRevision)
        XCTAssertTrue(harness.browserManager.tabManager.tabs(in: harness.space).contains { $0.id == historyTabID })
    }

    func testTogglingSelectionDoesNotNavigateAwayFromHistoryTab() throws {
        let harness = try makeHarness()
        let item = makeItem(url: URL(string: "https://example.com/select-only")!, title: "Select Only")

        harness.browserManager.openHistoryTab(in: harness.windowState)
        let historyTab = try XCTUnwrap(harness.browserManager.currentTab(for: harness.windowState))
        let historyTabID = historyTab.id
        let historyURL = historyTab.url
        let routingRevision = harness.windowState.nativeSurfaceRoutingRevision
        let tabCount = harness.browserManager.tabManager.tabs(in: harness.space).count
        let viewModel = HistoryPageViewModel(browserManager: harness.browserManager, windowState: harness.windowState)

        viewModel.toggleSelection(item)

        let currentTab = try XCTUnwrap(harness.browserManager.currentTab(for: harness.windowState))
        XCTAssertEqual(viewModel.selectionCount, 1)
        XCTAssertEqual(currentTab.id, historyTabID)
        XCTAssertEqual(currentTab.url, historyURL)
        XCTAssertTrue(currentTab.representsSumiHistorySurface)
        XCTAssertFalse(currentTab.requiresPrimaryWebView)
        XCTAssertEqual(harness.windowState.nativeSurfaceRoutingRevision, routingRevision)
        XCTAssertEqual(harness.browserManager.tabManager.tabs(in: harness.space).count, tabCount)
    }

    func testSelectionCountAndSearchPrunesHiddenSelection() async throws {
        let harness = try makeHarness()
        try await recordVisit(
            url: URL(string: "https://example.com/a")!,
            title: "Alpha",
            at: "2026-04-23T10:00:00Z",
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://example.org/b")!,
            title: "Beta",
            at: "2026-04-23T09:00:00Z",
            harness: harness
        )
        let viewModel = await makeLoadedViewModel(harness: harness)
        let items = await waitForVisibleItems(in: viewModel, minimumCount: 2)
        XCTAssertEqual(items.count, 2)

        items.forEach(viewModel.toggleSelection)
        XCTAssertEqual(viewModel.selectionCount, 2)

        viewModel.searchText = "Alpha"
        await drainMainQueue()

        XCTAssertEqual(viewModel.selectionCount, 1)
        XCTAssertEqual(viewModel.sections.flatMap(\.items).map(\.title), ["Alpha"])
    }

    func testSelectAllVisibleItemsSelectsOnlyFilteredRows() async throws {
        let harness = try makeHarness()
        try await recordVisit(
            url: URL(string: "https://www.youtube.com/watch?v=1")!,
            title: "YouTube",
            at: "2026-04-23T10:00:00Z",
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://m.youtube.com/watch?v=2")!,
            title: "YouTube Mobile",
            at: "2026-04-23T09:00:00Z",
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://reddit.com/r/browsers")!,
            title: "Reddit",
            at: "2026-04-23T08:00:00Z",
            harness: harness
        )
        let viewModel = await makeLoadedViewModel(harness: harness)
        let items = await waitForVisibleItems(in: viewModel, minimumCount: 3)
        let youtubeItem = try XCTUnwrap(items.first { $0.siteDomain == "youtube.com" })

        viewModel.showAllHistory(from: youtubeItem)
        await drainMainQueue()

        let filteredItems = viewModel.sections.flatMap(\.items)
        XCTAssertEqual(filteredItems.count, 2)
        XCTAssertTrue(filteredItems.allSatisfy { $0.siteDomain == "youtube.com" })

        viewModel.selectAllVisibleItems()

        XCTAssertEqual(viewModel.selectionCount, 2)
        XCTAssertTrue(viewModel.allVisibleItemsSelected)
    }

    func testOpenSelectedItemsOpensURLsInVisibleOrderAndDeduplicates() async throws {
        let harness = try makeHarness()
        let newestURL = URL(string: "https://newest.example/path")!
        let oldestURL = URL(string: "https://oldest.example/path")!
        try await recordVisit(url: oldestURL, title: "Oldest", at: "2026-04-23T08:00:00Z", harness: harness)
        try await recordVisit(url: newestURL, title: "Newest", at: "2026-04-23T10:00:00Z", harness: harness)
        let viewModel = await makeLoadedViewModel(harness: harness)
        let items = await waitForVisibleItems(in: viewModel, minimumCount: 2)
        XCTAssertEqual(items.map(\.url), [newestURL, oldestURL])

        items.forEach(viewModel.toggleSelection)
        viewModel.openSelectedItems()

        let tabs = harness.browserManager.tabManager.allTabs()
        XCTAssertEqual(harness.browserManager.currentTab(for: harness.windowState)?.url, newestURL)
        XCTAssertEqual(tabs.filter { $0.url == newestURL }.count, 1)
        XCTAssertEqual(tabs.filter { $0.url == oldestURL }.count, 1)
    }

    func testDeleteSelectedNormalVisitRemovesOnlyThatVisitAndClearsSelection() async throws {
        let harness = try makeHarness()
        let selectedURL = URL(string: "https://example.com/delete")!
        let remainingURL = URL(string: "https://example.org/keep")!
        try await recordVisit(url: selectedURL, title: "Delete", at: "2026-04-23T10:00:00Z", harness: harness)
        try await recordVisit(url: remainingURL, title: "Keep", at: "2026-04-23T09:00:00Z", harness: harness)
        let viewModel = await makeLoadedViewModel(harness: harness)
        let selectedItemMatch = await waitForVisibleItem(in: viewModel) { $0.url == selectedURL }
        let selectedItem = try XCTUnwrap(selectedItemMatch)

        viewModel.toggleSelection(selectedItem)
        await viewModel.deleteSelectedItemsNow()

        let remainingVisits = await harness.browserManager.historyManager.historyPage(
            query: .rangeFilter(.all),
            limit: 10
        ).items
        XCTAssertEqual(remainingVisits.map(\.url), [remainingURL])
        XCTAssertEqual(viewModel.selectionCount, 0)
    }

    func testDeleteSelectedSiteAggregateRemovesDomain() async throws {
        let harness = try makeHarness(confirmDeletion: { _, _ in true })
        try await recordVisit(
            url: URL(string: "https://example.com/delete")!,
            title: "Delete",
            at: "2026-04-23T10:00:00Z",
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://www.example.com/docs")!,
            title: "Docs",
            at: "2026-04-22T10:00:00Z",
            harness: harness
        )
        try await recordVisit(
            url: URL(string: "https://other.com/keep")!,
            title: "Keep",
            at: "2026-04-23T09:00:00Z",
            harness: harness
        )
        let viewModel = await makeLoadedViewModel(harness: harness)

        viewModel.selectRange(.allSites)
        let siteItemMatch = await waitForVisibleItem(in: viewModel) {
            $0.isSiteAggregate && $0.domain == "example.com"
        }
        let siteItem = try XCTUnwrap(siteItemMatch)

        viewModel.toggleSelection(siteItem)
        await viewModel.deleteSelectedItemsNow()

        let remainingVisits = await harness.browserManager.historyManager.historyPage(
            query: .rangeFilter(.all),
            limit: 10
        ).items
        XCTAssertEqual(remainingVisits.map(\.domain), ["other.com"])
        XCTAssertEqual(viewModel.selectionCount, 0)
    }

    private struct Harness {
        let browserManager: BrowserManager
        let windowState: BrowserWindowState
        let space: Space
        let profile: Profile
        let makeViewModel: () -> HistoryPageViewModel
    }

    private func makeHarness(
        confirmDeletion: @escaping @MainActor (_ title: String, _ message: String) -> Bool = { _, _ in true }
    ) throws -> Harness {
        let container = try ModelContainer(
            for: SumiStartupPersistence.schema,
            configurations: [ModelConfiguration(isStoredInMemoryOnly: true)]
        )
        let context = ModelContext(container)
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let space = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.modelContext = context
        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.historyManager = HistoryManager(context: context, profileId: profile.id)
        browserManager.windowRegistry = windowRegistry
        browserManager.tabManager.spaces = [space]
        browserManager.tabManager.currentSpace = space

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = space.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return Harness(
            browserManager: browserManager,
            windowState: windowState,
            space: space,
            profile: profile,
            makeViewModel: {
                HistoryPageViewModel(
                    browserManager: browserManager,
                    windowState: windowState,
                    confirmDeletion: confirmDeletion
                )
            }
        )
    }

    private func makeLoadedViewModel(harness: Harness) async -> HistoryPageViewModel {
        let viewModel = harness.makeViewModel()
        viewModel.appear()
        await drainMainQueue()
        return viewModel
    }

    private func recordVisit(
        url: URL,
        title: String,
        at timestamp: String,
        harness: Harness
    ) async throws {
        let baselineRevision = harness.browserManager.historyManager.revision
        _ = harness.browserManager.historyManager.addVisit(
            url: url,
            title: title,
            timestamp: date(timestamp),
            tabId: nil,
            profileId: harness.profile.id
        )
        for _ in 0..<30 {
            if harness.browserManager.historyManager.revision > baselineRevision {
                return
            }
            await drainMainQueue()
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    private func makeItem(url: URL, title: String) -> HistoryListItem {
        let visitID = VisitIdentifier(uuid: UUID().uuidString, url: url, date: fixedReferenceDate)
        let domain = HistoryDomainResolver.normalizedDomain(for: url)
        return HistoryListItem(
            id: visitID.description,
            visitID: visitID,
            url: url,
            title: title,
            domain: domain,
            siteDomain: HistoryDomainResolver.siteDomain(for: url),
            visitedAt: fixedReferenceDate,
            relativeDay: "Today",
            timeText: "12:00",
            visitCount: 1,
            isSiteAggregate: false
        )
    }

    private func drainMainQueue() async {
        await Task.yield()
        try? await Task.sleep(nanoseconds: 10_000_000)
        await Task.yield()
    }

    private func waitForVisibleItems(
        in viewModel: HistoryPageViewModel,
        minimumCount: Int
    ) async -> [HistoryListItem] {
        for _ in 0..<10 {
            let items = viewModel.sections.flatMap(\.items)
            if items.count >= minimumCount {
                return items
            }
            await drainMainQueue()
        }
        return viewModel.sections.flatMap(\.items)
    }

    private func waitForVisibleItem(
        in viewModel: HistoryPageViewModel,
        matching predicate: (HistoryListItem) -> Bool
    ) async -> HistoryListItem? {
        for _ in 0..<10 {
            if let item = viewModel.sections.flatMap(\.items).first(where: predicate) {
                return item
            }
            await drainMainQueue()
        }
        return viewModel.sections.flatMap(\.items).first(where: predicate)
    }

    private func date(_ value: String) -> Date {
        ISO8601DateFormatter().date(from: value)!
    }
}
