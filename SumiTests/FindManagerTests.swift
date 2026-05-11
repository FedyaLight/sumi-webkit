import XCTest
@testable import Sumi

@MainActor
final class FindManagerTests: XCTestCase {
    func testPrivateFindOptionsKeepDuckDuckGoRawValues() {
        XCTAssertEqual(_WKFindOptions.showOverlay.rawValue, 1 << 5)
        XCTAssertEqual(_WKFindOptions.showFindIndicator.rawValue, 1 << 6)
        XCTAssertEqual(_WKFindOptions.showHighlight.rawValue, 1 << 7)
        XCTAssertEqual(_WKFindOptions.noIndexChange.rawValue, 1 << 8)
        XCTAssertEqual(_WKFindOptions.determineMatchIndex.rawValue, 1 << 9)
    }

    func testVisibleInitialFindUsesDuckDuckGoTwoPhaseOptions() async throws {
        let webView = RecordingFindInPageWebView()
        webView.results = [.found(matches: 6), .found(matches: 6)]
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")

        findInPage.show(with: webView)

        try await webView.waitForFindCallCount(2)
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
        findInPage.show(with: webView)
        try await webView.waitForFindCallCount(2)

        webView.events.removeAll()
        findInPage.show(with: webView)
        try await webView.waitForFindCallCount(1)
        XCTAssertEqual(
            webView.events,
            [
                .collapseSelectionToStart,
                .find("test", rawOptions: 881, maxCount: 1000),
            ]
        )

        webView.events.removeAll()
        findInPage.findNext()
        try await webView.waitForFindCallCount(1)
        XCTAssertEqual(webView.events, [.find("test", rawOptions: 113, maxCount: 1000)])

        webView.events.removeAll()
        findInPage.findPrevious()
        try await webView.waitForFindCallCount(1)
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
        findInPage.show(with: webView)
        try await webView.waitForFindCallCount(2)

        webView.events.removeAll()
        findInPage.model.find("testing")

        try await webView.waitForFindCallCount(1)
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

    func testPageInteractionSwitchesOverlayToHighlightWithoutChangingSelection() async throws {
        let webView = RecordingFindInPageWebView()
        webView.results = [.found(matches: 6), .found(matches: 6), .found(matches: 6), .found(matches: 6)]
        let findInPage = FindInPageTabExtension()
        findInPage.model.find("test")
        findInPage.show(with: webView)
        try await webView.waitForFindCallCount(2)

        webView.events.removeAll()
        findInPage.pageInteractionWillBegin()
        try await webView.waitForFindCallCount(1)

        XCTAssertEqual(
            webView.events,
            [
                .clearFindInPageState,
                .find("test", rawOptions: 401, maxCount: 1000),
            ]
        )
        XCTAssertEqual(findInPage.model.currentSelection, 1)
        XCTAssertTrue(webView.findRawOptions.allSatisfy { $0 & _WKFindOptions.showHighlight.rawValue != 0 })
        XCTAssertTrue(webView.findRawOptions.allSatisfy { $0 & _WKFindOptions.showOverlay.rawValue == 0 })
        XCTAssertTrue(webView.findRawOptions.allSatisfy { $0 & _WKFindOptions.showFindIndicator.rawValue == 0 })

        webView.events.removeAll()
        findInPage.pageInteractionWillBegin()
        XCTAssertTrue(webView.events.isEmpty)

        findInPage.findNext()
        try await webView.waitForFindCallCount(1)
        XCTAssertEqual(webView.events, [.find("test", rawOptions: 113, maxCount: 1000)])
        XCTAssertFalse(webView.findRawOptions.contains { $0 & _WKFindOptions.showHighlight.rawValue != 0 })
    }

    func testShowFindBarWithoutTabKeepsManagerHidden() {
        let manager = FindManager()

        manager.showFindBar()

        XCTAssertFalse(manager.isFindBarVisible)
    }

    func testUpdateCurrentTabWithoutSessionResetsVisibleState() {
        let manager = FindManager()

        manager.updateCurrentTab(nil)

        XCTAssertFalse(manager.isFindBarVisible)
        XCTAssertNil(manager.currentModel)
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

    func collapseSelectionToStart() async throws {
        events.append(.collapseSelectionToStart)
    }

    func deselectAll() async throws {
        events.append(.deselectAll)
    }

    func find(_ string: String, with options: _WKFindOptions, maxCount: UInt) async -> FocusableWKWebView.FindResult {
        events.append(.find(string, rawOptions: options.rawValue, maxCount: maxCount))
        return results.isEmpty ? .found(matches: 1) : results.removeFirst()
    }

    func clearFindInPageState() {
        events.append(.clearFindInPageState)
    }

    func waitForFindCallCount(_ expectedCount: Int) async throws {
        for _ in 0..<100 {
            if findRawOptions.count >= expectedCount {
                return
            }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        XCTFail("Timed out waiting for \(expectedCount) find calls; saw \(findRawOptions.count)")
    }
}
