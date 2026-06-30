import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserNavigationToolbarContextOwnerTests: XCTestCase {
    func testToolbarContextUsesBoundWindowForCurrentTabAndWebView() {
        let windowState = BrowserWindowState()
        let tab = makeTab("https://toolbar.example")
        let webView = WKWebView()
        let owner = makeOwner(
            currentTab: { requestedWindow in
                requestedWindow === windowState ? tab : nil
            },
            webView: { requestedTab, requestedWindow in
                requestedTab === tab && requestedWindow === windowState ? webView : nil
            }
        )

        let context = owner.navigationToolbarContext(for: windowState)

        XCTAssertIdentical(context.currentTab(), tab)
        XCTAssertIdentical(context.webView(tab), webView)
    }

    func testNavigationHistorySelectedURLOpensForegroundInWindowSpace() {
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        windowState.currentSpaceId = spaceId
        let sourceTab = makeTab("https://source.example")
        let targetURL = URL(string: "https://selected.example/path")!
        var openedURL: String?
        var openedContext: BrowserTabOpenContext?
        let owner = makeOwner(
            openNewTab: { urlString, context in
                openedURL = urlString
                openedContext = context
            }
        )

        owner
            .navigationHistoryContext(for: windowState)
            .openURLInNewTab(targetURL, true, sourceTab)

        XCTAssertEqual(openedURL, targetURL.absoluteString)
        guard let openedContext else {
            XCTFail("Expected selected navigation history URL to open a tab")
            return
        }
        XCTAssertIdentical(openedContext.windowState, windowState)
        XCTAssertIdentical(openedContext.sourceTab, sourceTab)
        XCTAssertEqual(openedContext.preferredSpaceId, spaceId)
        guard case .foreground(let activationWindow, let loadPolicy) = openedContext.activationPolicy else {
            XCTFail("Expected foreground activation for selected history URL")
            return
        }
        XCTAssertIdentical(activationWindow, windowState)
        XCTAssertEqual(loadPolicy, .deferred)
    }

    func testNavigationHistoryBackgroundURLOpensInWindowSpaceWithoutForegroundActivation() {
        let windowState = BrowserWindowState()
        let spaceId = UUID()
        windowState.currentSpaceId = spaceId
        let sourceTab = makeTab("https://source.example")
        let targetURL = URL(string: "https://background.example/path")!
        var openedContext: BrowserTabOpenContext?
        let owner = makeOwner(
            openNewTab: { _, context in
                openedContext = context
            }
        )

        owner
            .navigationHistoryContext(for: windowState)
            .openURLInNewTab(targetURL, false, sourceTab)

        guard let openedContext else {
            XCTFail("Expected background navigation history URL to open a tab")
            return
        }
        XCTAssertIdentical(openedContext.windowState, windowState)
        XCTAssertIdentical(openedContext.sourceTab, sourceTab)
        XCTAssertEqual(openedContext.preferredSpaceId, spaceId)
        guard case .background = openedContext.activationPolicy else {
            XCTFail("Expected background activation for unselected history URL")
            return
        }
    }

    func testNavigationHistoryNewWindowDelegatesURLs() {
        let windowState = BrowserWindowState()
        let urls = [
            URL(string: "https://first.example")!,
            URL(string: "https://second.example")!,
        ]
        var delegatedURLs: [URL] = []
        let owner = makeOwner(
            openHistoryURLsInNewWindow: { urls in
                delegatedURLs = urls
            }
        )

        owner
            .navigationHistoryContext(for: windowState)
            .openURLsInNewWindow(urls)

        XCTAssertEqual(delegatedURLs, urls)
    }

    private func makeOwner(
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab? = { _ in nil },
        webView: @escaping @MainActor (Tab, BrowserWindowState) -> WKWebView? = { _, _ in nil },
        activeWindow: @escaping @MainActor () -> BrowserWindowState? = { nil },
        openNewTab: @escaping @MainActor (String, BrowserTabOpenContext) -> Void = { _, _ in },
        openHistoryURLsInNewWindow: @escaping @MainActor ([URL]) -> Void = { _ in }
    ) -> BrowserNavigationToolbarContextOwner {
        BrowserNavigationToolbarContextOwner(
            dependencies: BrowserNavigationToolbarContextOwner.Dependencies(
                currentTab: currentTab,
                webView: webView,
                faviconService: {
                    BrowserManagerDataServices.productionFaviconService
                },
                faviconImageService: {
                    BrowserManagerDataServices.productionFaviconImageService
                },
                activeWindow: activeWindow,
                openNewTab: openNewTab,
                openHistoryURLsInNewWindow: openHistoryURLsInNewWindow
            )
        )
    }

    private func makeTab(_ url: String) -> Tab {
        Tab(
            url: URL(string: url)!,
            name: url,
            loadsCachedFaviconOnInit: false
        )
    }
}
