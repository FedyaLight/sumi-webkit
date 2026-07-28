@testable import Sumi
import Combine
import XCTest

@MainActor
final class FindManagerTests: XCTestCase {
    func testProgressPublishesCurrentAndTotalAtomically() {
        let model = FindInPageModel()
        var values: [FindInPageProgress?] = []
        let cancellable = model.$progress.sink { values.append($0) }

        model.update(progress: .init(currentSelection: 8, matchesFound: 10))

        XCTAssertEqual(values, [nil, .init(currentSelection: 8, matchesFound: 10)])
        withExtendedLifetime(cancellable) {}
    }

    func testUnknownMatchCountDoesNotPublishPartialProgress() async {
        let webView = RecordingFindInPageWebView()
        webView.results = [.found(matches: nil), .found(matches: nil)]
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")
        let searches = webView.expectSearchCallCount(2)

        findInPage.show(with: webView)

        await fulfillment(of: [searches], timeout: 1)
        XCTAssertNil(findInPage.model.progress)
        XCTAssertNil(findInPage.model.currentSelection)
        XCTAssertNil(findInPage.model.matchesFound)
    }

    func testChromePresentationRequiresUnsuppressedActivePlacement() {
        XCTAssertTrue(FindInPageChromePresentation(
            isActiveWindow: true,
            isFindBarVisible: true,
            isModalSuppressed: false,
            isPlacementSuppressed: false
        ).isPresented)

        for presentation in [
            FindInPageChromePresentation(
                isActiveWindow: false,
                isFindBarVisible: true,
                isModalSuppressed: false,
                isPlacementSuppressed: false
            ),
            FindInPageChromePresentation(
                isActiveWindow: true,
                isFindBarVisible: false,
                isModalSuppressed: false,
                isPlacementSuppressed: false
            ),
            FindInPageChromePresentation(
                isActiveWindow: true,
                isFindBarVisible: true,
                isModalSuppressed: true,
                isPlacementSuppressed: false
            ),
            FindInPageChromePresentation(
                isActiveWindow: true,
                isFindBarVisible: true,
                isModalSuppressed: false,
                isPlacementSuppressed: true
            ),
        ] {
            XCTAssertFalse(presentation.isPresented)
        }
    }

    func testPrivateFindOptionsKeepDuckDuckGoRawValues() {
        XCTAssertEqual(_WKFindOptions.showOverlay.rawValue, 1 << 5)
        XCTAssertEqual(_WKFindOptions.showFindIndicator.rawValue, 1 << 6)
        XCTAssertEqual(_WKFindOptions.showHighlight.rawValue, 1 << 7)
        XCTAssertEqual(_WKFindOptions.atWordStarts.rawValue, 1 << 1)
        XCTAssertEqual(_WKFindOptions.treatMedialCapitalAsWordStart.rawValue, 1 << 2)
        XCTAssertEqual(_WKFindOptions.noIndexChange.rawValue, 1 << 8)
        XCTAssertEqual(_WKFindOptions.determineMatchIndex.rawValue, 1 << 9)
    }

    func testVisibleInitialFindUsesTwoPhaseSemanticSearch() async throws {
        let webView = RecordingFindInPageWebView()
        webView.results = [.found(matches: 6), .found(matches: 6)]
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")
        let searchCalls = webView.expectSearchCallCount(2)

        findInPage.show(with: webView)

        await fulfillment(of: [searchCalls], timeout: 1)
        XCTAssertEqual(
            webView.events,
            [
                .prepareFindSession,
                .search(.init(query: "test")),
                .dismissFindSession,
                .search(.init(
                    query: "test",
                    preservesSelection: true,
                    showsOverlay: true
                )),
            ]
        )
    }

    func testRepeatShowNextPreviousAndCloseUseSemanticSearch() async throws {
        let webView = RecordingFindInPageWebView()
        webView.results = [
            .found(matches: 6),
            .found(matches: 6),
            .found(matches: 6),
            .found(matches: 6),
            .found(matches: 6),
        ]
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")
        let initialFindCalls = webView.expectSearchCallCount(2)
        findInPage.show(with: webView)
        await fulfillment(of: [initialFindCalls], timeout: 1)

        webView.events.removeAll()
        let repeatFindCall = webView.expectSearchCallCount(1)
        findInPage.show(with: webView)
        await fulfillment(of: [repeatFindCall], timeout: 1)
        XCTAssertEqual(
            webView.events,
            [
                .search(.init(
                    query: "test",
                    preservesSelection: true,
                    showsOverlay: true,
                    determinesMatchIndex: true
                )),
            ]
        )

        webView.events.removeAll()
        let nextFindCall = webView.expectSearchCallCount(1)
        findInPage.findNext()
        await fulfillment(of: [nextFindCall], timeout: 1)
        XCTAssertEqual(
            webView.events,
            [.search(.init(query: "test", showsOverlay: true))]
        )

        webView.events.removeAll()
        let previousFindCall = webView.expectSearchCallCount(1)
        findInPage.findPrevious()
        await fulfillment(of: [previousFindCall], timeout: 1)
        XCTAssertEqual(
            webView.events,
            [.search(.init(query: "test", direction: .backward, showsOverlay: true))]
        )

        webView.events.removeAll()
        findInPage.close()
        XCTAssertEqual(webView.events, [.dismissFindSession])
    }

    func testReopeningFindInPageRestoresCurrentMatch() async throws {
        let webView = RecordingFindInPageWebView()
        webView.results = Array(repeating: .found(matches: 10), count: 5)
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")

        let initialFindCalls = webView.expectSearchCallCount(2)
        findInPage.show(with: webView)
        await fulfillment(of: [initialFindCalls], timeout: 1)

        let nextFindCall = webView.expectSearchCallCount(3)
        findInPage.findNext()
        await fulfillment(of: [nextFindCall], timeout: 1)
        XCTAssertEqual(findInPage.model.currentSelection, 2)

        findInPage.close()
        webView.events.removeAll()

        let restoredFindCalls = webView.expectSearchCallCount(2)
        findInPage.show(with: webView)
        await fulfillment(of: [restoredFindCalls], timeout: 1)

        XCTAssertEqual(
            webView.events,
            [
                .search(.init(
                    query: "test",
                    preservesSelection: true,
                    determinesMatchIndex: true
                )),
                .dismissFindSession,
                .search(.init(
                    query: "test",
                    preservesSelection: true,
                    showsOverlay: true
                )),
            ]
        )
        XCTAssertEqual(findInPage.model.currentSelection, 2)
        XCTAssertEqual(findInPage.model.matchesFound, 10)
    }

    func testNavigationInvalidatesRestorableFindProgress() async throws {
        let webView = RecordingFindInPageWebView()
        webView.results = Array(repeating: .found(matches: 10), count: 5)
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")

        let initialFindCalls = webView.expectSearchCallCount(2)
        findInPage.show(with: webView)
        await fulfillment(of: [initialFindCalls], timeout: 1)

        let nextFindCall = webView.expectSearchCallCount(3)
        findInPage.findNext()
        await fulfillment(of: [nextFindCall], timeout: 1)
        XCTAssertEqual(findInPage.model.currentSelection, 2)

        findInPage.navigationDidStart()
        webView.events.removeAll()

        let newDocumentFindCalls = webView.expectSearchCallCount(2)
        findInPage.show(with: webView)
        await fulfillment(of: [newDocumentFindCalls], timeout: 1)

        XCTAssertEqual(
            webView.events,
            [
                .prepareFindSession,
                .search(.init(query: "test")),
                .dismissFindSession,
                .search(.init(
                    query: "test",
                    preservesSelection: true,
                    showsOverlay: true
                )),
            ]
        )
        XCTAssertEqual(findInPage.model.currentSelection, 1)
        XCTAssertEqual(findInPage.model.matchesFound, 10)
    }

    func testActiveTextChangeKeepsCurrentMatchUsingDuckDuckGoOptions() async throws {
        let webView = RecordingFindInPageWebView()
        webView.results = [.found(matches: 6), .found(matches: 6), .found(matches: 4)]
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")
        let initialFindCalls = webView.expectSearchCallCount(2)
        findInPage.show(with: webView)
        await fulfillment(of: [initialFindCalls], timeout: 1)

        webView.events.removeAll()
        let updatedFindCall = webView.expectSearchCallCount(1)
        findInPage.model.find("testing")

        await fulfillment(of: [updatedFindCall], timeout: 1)
        XCTAssertEqual(
            webView.events,
            [
                .search(.init(
                    query: "testing",
                    preservesSelection: true,
                    showsOverlay: true
                )),
            ]
        )
        XCTAssertEqual(findInPage.model.currentSelection, 1)
        XCTAssertEqual(findInPage.model.matchesFound, 4)
    }

    func testClosingBeforeDebouncedQueryChangeCannotRestoreOldProgress() async {
        let webView = RecordingFindInPageWebView()
        webView.results = Array(repeating: .found(matches: 10), count: 4)
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")

        let initialSearches = webView.expectSearchCallCount(2)
        findInPage.show(with: webView)
        await fulfillment(of: [initialSearches], timeout: 1)
        XCTAssertEqual(findInPage.model.progress, .init(currentSelection: 1, matchesFound: 10))

        findInPage.model.find("testing")
        findInPage.close()
        webView.events.removeAll()

        let reopenedSearches = webView.expectSearchCallCount(2)
        findInPage.show(with: webView)
        await fulfillment(of: [reopenedSearches], timeout: 1)

        XCTAssertEqual(
            webView.events,
            [
                .prepareFindSession,
                .search(.init(query: "testing")),
                .dismissFindSession,
                .search(.init(
                    query: "testing",
                    preservesSelection: true,
                    showsOverlay: true
                )),
            ]
        )
        XCTAssertEqual(findInPage.model.progress, .init(currentSelection: 1, matchesFound: 10))
    }

    func testChangingPhysicalPresentationInvalidatesRestorableProgress() async {
        let firstWebView = RecordingFindInPageWebView()
        firstWebView.results = Array(repeating: .found(matches: 10), count: 3)
        let secondWebView = RecordingFindInPageWebView()
        secondWebView.results = Array(repeating: .found(matches: 10), count: 2)
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")

        let initialSearches = firstWebView.expectSearchCallCount(2)
        findInPage.show(with: firstWebView)
        await fulfillment(of: [initialSearches], timeout: 1)
        let nextSearch = firstWebView.expectSearchCallCount(3)
        findInPage.findNext()
        await fulfillment(of: [nextSearch], timeout: 1)
        XCTAssertEqual(findInPage.model.currentSelection, 2)
        findInPage.close()

        let replacementSearches = secondWebView.expectSearchCallCount(2)
        findInPage.show(with: secondWebView)
        await fulfillment(of: [replacementSearches], timeout: 1)

        XCTAssertEqual(
            secondWebView.events,
            [
                .prepareFindSession,
                .search(.init(query: "test")),
                .dismissFindSession,
                .search(.init(
                    query: "test",
                    preservesSelection: true,
                    showsOverlay: true
                )),
            ]
        )
        XCTAssertEqual(findInPage.model.currentSelection, 1)
    }

    func testShowFindBarWithoutTabKeepsManagerHidden() {
        let manager = FindManager()

        manager.showFindBar(for: nil, in: nil)

        XCTAssertFalse(manager.isFindBarVisible)
    }

    func testUpdateCurrentTabWithoutSessionResetsVisibleState() {
        let manager = FindManager()

        manager.updateCurrentTab(nil, in: nil)

        XCTAssertFalse(manager.isFindBarVisible)
        XCTAssertNil(manager.currentModel)
    }

    func testShowFindBarUsesProvidedWindowScopedWebView() {
        let manager = FindManager()
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let webView = FocusableWKWebView()
        let windowId = UUID()
        var lookup: (tabId: UUID, windowId: UUID)?
        tab.navigationRuntime.findInPageRuntime = TabFindInPageRuntime { tabId, resolvedWindowId in
            lookup = (tabId, resolvedWindowId)
            return webView
        }

        manager.showFindBar(for: tab, in: windowId)

        XCTAssertEqual(lookup?.tabId, tab.id)
        XCTAssertEqual(lookup?.windowId, windowId)
        XCTAssertEqual(manager.findFieldFocusGeneration, 1)
        XCTAssertIdentical(manager.currentModel, tab.findInPage.model)
    }

    func testRepeatShowFindBarIssuesOneSemanticSearch() async {
        let webView = RecordingFindInPageWebView()
        webView.results = Array(repeating: .found(matches: 6), count: 3)
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let windowId = UUID()
        let manager = FindManager { _, _ in webView }
        tab.findInPage.model.find("test")

        let initialSearches = webView.expectSearchCallCount(2)
        manager.showFindBar(for: tab, in: windowId)
        await fulfillment(of: [initialSearches], timeout: 1)
        webView.events.removeAll()

        let repeatedSearch = webView.expectSearchCallCount(1)
        manager.showFindBar(for: tab, in: windowId)
        await fulfillment(of: [repeatedSearch], timeout: 1)

        XCTAssertEqual(
            webView.searchRequests,
            [
                .init(
                    query: "test",
                    preservesSelection: true,
                    showsOverlay: true,
                    determinesMatchIndex: true
                ),
            ]
        )
        XCTAssertEqual(manager.findFieldFocusGeneration, 2)
    }

    func testSameVisibleRoutingUpdateDoesNotRepeatSearch() async {
        let webView = RecordingFindInPageWebView()
        webView.results = Array(repeating: .found(matches: 6), count: 2)
        let tab = Tab(loadsCachedFaviconOnInit: false)
        let windowId = UUID()
        let manager = FindManager { _, _ in webView }
        tab.findInPage.model.find("test")

        let initialSearches = webView.expectSearchCallCount(2)
        manager.showFindBar(for: tab, in: windowId)
        await fulfillment(of: [initialSearches], timeout: 1)
        webView.events.removeAll()

        manager.updateCurrentTab(tab, in: windowId)
        await Task.yield()

        XCTAssertTrue(webView.searchRequests.isEmpty)
    }
}

@MainActor
private final class RecordingFindInPageWebView: FindInPageWebView {
    enum Event: Equatable {
        case prepareFindSession
        case search(FindInPageSearchRequest)
        case dismissFindSession
    }

    var events: [Event] = []
    var results: [FindInPageSearchResult] = []
    var documentKind: FindInPageDocumentKind = .html
    private var expectedSearchCalls: (count: Int, expectation: XCTestExpectation)?

    var searchRequests: [FindInPageSearchRequest] {
        events.compactMap {
            guard case .search(let request) = $0 else { return nil }
            return request
        }
    }

    func prepareFindSession() async -> FindInPageDocumentKind {
        events.append(.prepareFindSession)
        return documentKind
    }

    func search(_ request: FindInPageSearchRequest) async -> FindInPageSearchResult {
        events.append(.search(request))
        if let expectedSearchCalls,
           searchRequests.count >= expectedSearchCalls.count {
            self.expectedSearchCalls = nil
            expectedSearchCalls.expectation.fulfill()
        }
        return results.isEmpty ? .found(matches: 1) : results.removeFirst()
    }

    func dismissFindSession() {
        events.append(.dismissFindSession)
    }

    func expectSearchCallCount(_ count: Int) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "received \(count) search calls")
        expectedSearchCalls = (count, expectation)
        return expectation
    }
}
