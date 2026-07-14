@testable import Sumi
import XCTest

@MainActor
final class FindManagerTests: XCTestCase {
    func testPrivateFindOptionsKeepDuckDuckGoRawValues() {
        XCTAssertEqual(_WKFindOptions.showOverlay.rawValue, 1 << 5)
        XCTAssertEqual(_WKFindOptions.showFindIndicator.rawValue, 1 << 6)
        XCTAssertEqual(_WKFindOptions.showHighlight.rawValue, 1 << 7)
        XCTAssertEqual(_WKFindOptions.atWordStarts.rawValue, 1 << 1)
        XCTAssertEqual(_WKFindOptions.treatMedialCapitalAsWordStart.rawValue, 1 << 2)
        XCTAssertEqual(_WKFindOptions.noIndexChange.rawValue, 1 << 8)
        XCTAssertEqual(_WKFindOptions.determineMatchIndex.rawValue, 1 << 9)
    }

    func testVisibleInitialFindUsesDuckDuckGoTwoPhaseOptions() async throws {
        let webView = RecordingFindInPageWebView()
        webView.results = [.found(matches: 6), .found(matches: 6)]
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")
        let findCalls = webView.expectFindCallCount(2)

        findInPage.show(with: webView)

        await fulfillment(of: [findCalls], timeout: 1)
        XCTAssertEqual(
            webView.events,
            [
                .clearFindInPageState,
                .deselectAll,
                .readMimeType,
                .find("test", rawOptions: 81, maxCount: 1000),
                .clearFindInPageState,
                .collapseSelectionToStart,
                .find("test", rawOptions: 369, maxCount: 1000),
            ]
        )
        XCTAssertFalse(webView.findRawOptions.contains { $0 & _WKFindOptions.showHighlight.rawValue != 0 })
    }

    func testRepeatShowNextPreviousAndCloseUseDuckDuckGoOptions() async throws {
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
        let initialFindCalls = webView.expectFindCallCount(2)
        findInPage.show(with: webView)
        await fulfillment(of: [initialFindCalls], timeout: 1)

        webView.events.removeAll()
        let repeatFindCall = webView.expectFindCallCount(1)
        findInPage.show(with: webView)
        await fulfillment(of: [repeatFindCall], timeout: 1)
        XCTAssertEqual(
            webView.events,
            [
                .collapseSelectionToStart,
                .find("test", rawOptions: 881, maxCount: 1000),
            ]
        )

        webView.events.removeAll()
        let nextFindCall = webView.expectFindCallCount(1)
        findInPage.findNext()
        await fulfillment(of: [nextFindCall], timeout: 1)
        XCTAssertEqual(webView.events, [.find("test", rawOptions: 113, maxCount: 1000)])

        webView.events.removeAll()
        let previousFindCall = webView.expectFindCallCount(1)
        findInPage.findPrevious()
        await fulfillment(of: [previousFindCall], timeout: 1)
        XCTAssertEqual(webView.events, [.find("test", rawOptions: 121, maxCount: 1000)])

        webView.events.removeAll()
        findInPage.close()
        XCTAssertEqual(webView.events, [.clearFindInPageState])
        XCTAssertFalse(webView.findRawOptions.contains { $0 & _WKFindOptions.showHighlight.rawValue != 0 })
    }

    func testActiveTextChangeKeepsCurrentMatchUsingDuckDuckGoOptions() async throws {
        let webView = RecordingFindInPageWebView()
        webView.results = [.found(matches: 6), .found(matches: 6), .found(matches: 4)]
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")
        let initialFindCalls = webView.expectFindCallCount(2)
        findInPage.show(with: webView)
        await fulfillment(of: [initialFindCalls], timeout: 1)

        webView.events.removeAll()
        let updatedFindCall = webView.expectFindCallCount(1)
        findInPage.model.find("testing")

        await fulfillment(of: [updatedFindCall], timeout: 1)
        XCTAssertEqual(
            webView.events,
            [
                .collapseSelectionToStart,
                .find("testing", rawOptions: 369, maxCount: 1000),
            ]
        )
        XCTAssertEqual(findInPage.model.currentSelection, 1)
        XCTAssertEqual(findInPage.model.matchesFound, 4)
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
}

@MainActor
private final class RecordingFindInPageWebView: FindInPageWebView {
    enum Event: Equatable {
        case clearFindInPageState
        case collapseSelectionToStart
        case deselectAll
        case readMimeType
        case find(String, rawOptions: UInt, maxCount: UInt)
    }

    var events: [Event] = []
    var results: [FocusableWKWebView.FindResult] = []
    private var expectedFindCalls: (count: Int, expectation: XCTestExpectation)?

    var findRawOptions: [UInt] {
        events.compactMap {
            guard case .find(_, let rawOptions, _) = $0 else { return nil }
            return rawOptions
        }
    }

    var mimeType: String? {
        get async {
            events.append(.readMimeType)
            return "text/html"
        }
    }

    func collapseSelectionToStart() async {
        events.append(.collapseSelectionToStart)
    }

    func deselectAll() async {
        events.append(.deselectAll)
    }

    func find(_ string: String, with options: _WKFindOptions, maxCount: UInt) async -> FocusableWKWebView.FindResult {
        events.append(.find(string, rawOptions: options.rawValue, maxCount: maxCount))
        if let expectedFindCalls,
           findRawOptions.count >= expectedFindCalls.count {
            self.expectedFindCalls = nil
            expectedFindCalls.expectation.fulfill()
        }
        return results.isEmpty ? .found(matches: 1) : results.removeFirst()
    }

    func clearFindInPageState() {
        events.append(.clearFindInPageState)
    }

    func expectFindCallCount(_ count: Int) -> XCTestExpectation {
        let expectation = XCTestExpectation(description: "received \(count) find calls")
        expectedFindCalls = (count, expectation)
        return expectation
    }
}
