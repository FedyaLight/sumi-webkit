import WebKit
import XCTest

@testable import Sumi

@MainActor
final class HistoryMenuModelTests: XCTestCase {
    func testNavigationHistoryButtonMenuOrderingMatchesDDG() {
        let current = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/current"),
            title: "Current",
            isCurrent: true
        )
        let oldestBack = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/oldest"),
            title: "Oldest Back",
            isCurrent: false
        )
        let middleBack = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/middle"),
            title: "Middle Back",
            isCurrent: false
        )
        let newestBack = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/newest"),
            title: "Newest Back",
            isCurrent: false
        )
        let nextForward = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/next"),
            title: "Next Forward",
            isCurrent: false
        )
        let laterForward = SumiNavigationHistoryMenuItem(
            url: URL(string: "https://example.com/later"),
            title: "Later Forward",
            isCurrent: false
        )

        let backOrder = SumiNavigationHistoryMenuModel.orderedItems(
            current: current,
            backItems: [oldestBack, middleBack, newestBack],
            forwardItems: [nextForward, laterForward],
            direction: .back
        )
        XCTAssertEqual(backOrder.map(\.title), ["Current", "Newest Back", "Middle Back", "Oldest Back"])
        XCTAssertTrue(backOrder[0].isCurrent)

        let forwardOrder = SumiNavigationHistoryMenuModel.orderedItems(
            current: current,
            backItems: [oldestBack, middleBack, newestBack],
            forwardItems: [nextForward, laterForward],
            direction: .forward
        )
        XCTAssertEqual(forwardOrder.map(\.title), ["Current", "Next Forward", "Later Forward"])
        XCTAssertTrue(forwardOrder[0].isCurrent)
    }

    func testURLOnlyCurrentTabNavigationUsesHistoryContext() {
        let sourceTab = Tab(
            url: URL(string: "https://source.example")!,
            name: "Source",
            loadsCachedFaviconOnInit: false
        )
        let targetURL = URL(string: "https://target.example/path")!
        let item = SumiNavigationHistoryMenuItem(
            url: targetURL,
            title: "Target",
            isCurrent: false
        )
        var openedURL: URL?
        weak var openedSourceTab: Tab?
        let context = makeHistoryContext(
            openURLInCurrentTab: { url, tab in
                openedURL = url
                openedSourceTab = tab
            }
        )

        SumiNavigationHistoryMenuModel.navigate(
            to: item,
            tab: sourceTab,
            webView: nil,
            historyContext: context,
            event: nil
        )

        XCTAssertEqual(openedURL, targetURL)
        XCTAssertIdentical(openedSourceTab, sourceTab)
        XCTAssertEqual(sourceTab.url, URL(string: "https://source.example")!)
    }

    func testBackForwardListItemMustBelongToActiveWebViewBeforeRawGo() async throws {
        let sourceTab = Tab(
            url: URL(string: "https://source.example")!,
            name: "Source",
            loadsCachedFaviconOnInit: false
        )
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("HistoryMenuModelTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(
            at: directory,
            withIntermediateDirectories: true
        )
        defer {
            try? FileManager.default.removeItem(at: directory)
        }
        let firstURL = directory.appendingPathComponent("first.html")
        let secondURL = directory.appendingPathComponent("second.html")
        try "<html><body>first</body></html>".write(to: firstURL, atomically: true, encoding: .utf8)
        try "<html><body>second</body></html>".write(to: secondURL, atomically: true, encoding: .utf8)
        let menuWebView = WKWebView()
        let activeWebView = WKWebView()
        await loadFile(firstURL, in: menuWebView)
        await loadFile(secondURL, in: menuWebView)
        let items = SumiNavigationHistoryMenuModel.items(
            direction: .back,
            tab: sourceTab,
            webView: menuWebView
        )
        let staleBackItem = items.first { $0.url == firstURL }
        guard let staleBackItem else {
            XCTFail("Expected menu WebView to expose first page as a back item")
            return
        }
        var openedURL: URL?
        weak var openedSourceTab: Tab?
        let context = makeHistoryContext(
            openURLInCurrentTab: { url, tab in
                openedURL = url
                openedSourceTab = tab
            }
        )

        SumiNavigationHistoryMenuModel.navigate(
            to: staleBackItem,
            tab: sourceTab,
            webView: activeWebView,
            historyContext: context,
            event: nil
        )

        XCTAssertEqual(openedURL, firstURL)
        XCTAssertIdentical(openedSourceTab, sourceTab)
    }

    private func makeHistoryContext(
        openURLInCurrentTab: @escaping (URL, Tab?) -> Void = { _, _ in },
        openURLInNewTab: @escaping (URL, Bool, Tab?) -> Void = { _, _, _ in },
        openURLsInNewWindow: @escaping ([URL]) -> Void = { _ in }
    ) -> SumiNavigationHistoryContext {
        SumiNavigationHistoryContext(
            faviconService: BrowserManagerDataServices.productionFaviconService,
            faviconImageService: BrowserManagerDataServices.productionFaviconImageService,
            openURLInCurrentTab: openURLInCurrentTab,
            openURLInNewTab: openURLInNewTab,
            openURLsInNewWindow: openURLsInNewWindow
        )
    }

    private func loadFile(_ url: URL, in webView: WKWebView) async {
        let didFinish = expectation(description: "Loaded \(url.absoluteString)")
        let delegate = HistoryMenuNavigationDelegateBox {
            didFinish.fulfill()
        }
        webView.navigationDelegate = delegate
        webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        await fulfillment(of: [didFinish], timeout: 5.0)
        webView.navigationDelegate = nil
        _ = delegate
    }
}

private final class HistoryMenuNavigationDelegateBox: NSObject, WKNavigationDelegate {
    private let didFinish: () -> Void

    init(didFinish: @escaping () -> Void) {
        self.didFinish = didFinish
    }

    func webView(
        _: WKWebView,
        didFinish _: WKNavigation! // swiftlint:disable:this implicitly_unwrapped_optional
    ) {
        didFinish()
    }
}
