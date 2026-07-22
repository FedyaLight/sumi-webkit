import WebKit
import XCTest

@testable import Sumi
import SumiDomain

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

    func testHistoryItemSourceIdentityRejectsDifferentWebView() {
        let firstURL = URL(string: "https://history-menu.test/first")!
        let menuWebView = WKWebView()
        let activeWebView = WKWebView()
        let staleHistoryItem = SumiNavigationHistoryMenuItem(
            url: firstURL,
            title: "First",
            sourceWebViewObjectID: ObjectIdentifier(menuWebView),
            isCurrent: false
        )

        XCTAssertTrue(
            SumiNavigationHistoryMenuModel.historyItem(
                staleHistoryItem,
                belongsTo: menuWebView
            )
        )
        XCTAssertFalse(
            SumiNavigationHistoryMenuModel.historyItem(
                staleHistoryItem,
                belongsTo: activeWebView
            )
        )
    }

    private func makeHistoryContext(
        openURLInCurrentTab: @escaping (URL, Tab?) -> Void = { _, _ in /* No-op. */ },
        openURLInNewTab: @escaping (URL, Bool, Tab?) -> Void = { _, _, _ in /* No-op. */ },
        openURLsInNewWindow: @escaping ([URL]) -> Void = { _ in /* No-op. */ }
    ) -> SumiNavigationHistoryContext {
        SumiNavigationHistoryContext(
            faviconService: TabDependencyIsolationDefaults.faviconService,
            faviconImageReader: TabDependencyIsolationDefaults.faviconCapabilities.images,
            openURLInCurrentTab: openURLInCurrentTab,
            openURLInNewTab: openURLInNewTab,
            openURLsInNewWindow: openURLsInNewWindow
        )
    }

}
