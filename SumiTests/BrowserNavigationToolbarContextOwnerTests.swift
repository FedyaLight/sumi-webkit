import WebKit
import XCTest

@testable import Sumi

@MainActor
final class NavigationToolbarContextOwnerTests: XCTestCase {
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

    func testNavigationHistoryCurrentURLUsesBoundWindowScopedAction() {
        let windowState = BrowserWindowState()
        let targetURL = URL(string: "https://current.example/path")!
        var openedURL: URL?
        weak var openedWindow: BrowserWindowState?
        let owner = makeOwner(
            openURLInCurrentTab: { url, windowState in
                openedURL = url
                openedWindow = windowState
            }
        )

        owner
            .navigationHistoryContext(for: windowState)
            .openURLInCurrentTab(targetURL, nil)

        XCTAssertEqual(openedURL, targetURL)
        XCTAssertIdentical(openedWindow, windowState)
    }

    func testNavigationHistoryDeadBoundWindowDoesNotRetargetToAnotherWindow() {
        var boundWindow: BrowserWindowState? = BrowserWindowState()
        weak var releasedBoundWindow: BrowserWindowState?
        releasedBoundWindow = boundWindow
        let targetURL = URL(string: "https://stale.example/path")!
        var openedCurrentURL: URL?
        var openedNewTabURL: String?
        let owner = makeOwner(
            openURLInCurrentTab: { url, _ in
                openedCurrentURL = url
            },
            openNewTab: { urlString, _ in
                openedNewTabURL = urlString
            }
        )

        let context = owner.navigationHistoryContext(for: boundWindow ?? preconditionFailure("Expected bound window"))
        boundWindow = nil

        XCTAssertNil(releasedBoundWindow)

        context.openURLInNewTab(targetURL, true, nil)
        context.openURLInCurrentTab(targetURL, nil)

        XCTAssertNil(openedNewTabURL)
        XCTAssertNil(openedCurrentURL)
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

    func testToolbarBackForwardActionsUseBoundWindow() {
        let windowState = BrowserWindowState()
        var backWindow: BrowserWindowState?
        var forwardWindow: BrowserWindowState?
        let owner = makeOwner(
            goBack: { windowState in
                backWindow = windowState
            },
            goForward: { windowState in
                forwardWindow = windowState
            }
        )

        let context = owner.navigationToolbarContext(for: windowState)
        context.goBack()
        context.goForward()

        XCTAssertIdentical(backWindow, windowState)
        XCTAssertIdentical(forwardWindow, windowState)
    }

    func testToolbarReloadActionUsesBoundWindow() {
        let windowState = BrowserWindowState()
        let tab = makeTab("https://reload.example")
        var reloadedTabId: UUID?
        var reloadedWindowId: UUID?
        let owner = makeOwner(
            reload: { tab, windowState in
                reloadedTabId = tab.id
                reloadedWindowId = windowState.id
            }
        )

        let context = owner.navigationToolbarContext(for: windowState)
        context.reload(tab)

        XCTAssertEqual(reloadedTabId, tab.id)
        XCTAssertEqual(reloadedWindowId, windowState.id)
    }

    private func makeOwner(
        currentTab: @escaping @MainActor (BrowserWindowState) -> Tab? = { _ in nil },
        webView: @escaping @MainActor (Tab, BrowserWindowState) -> WKWebView? = { _, _ in nil },
        openURLInCurrentTab: @escaping @MainActor (URL, BrowserWindowState) -> Void = { _, _ in /* No-op. */ },
        openNewTab: @escaping @MainActor (String, BrowserTabOpenContext) -> Void = { _, _ in /* No-op. */ },
        openHistoryURLsInNewWindow: @escaping @MainActor ([URL]) -> Void = { _ in /* No-op. */ },
        goBack: @escaping @MainActor (BrowserWindowState) -> Void = { _ in /* No-op. */ },
        goForward: @escaping @MainActor (BrowserWindowState) -> Void = { _ in /* No-op. */ },
        reload: @escaping @MainActor (Tab, BrowserWindowState) -> Void = { _, _ in /* No-op. */ }
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
                openURLInCurrentTab: openURLInCurrentTab,
                openNewTab: openNewTab,
                openHistoryURLsInNewWindow: openHistoryURLsInNewWindow,
                goBack: goBack,
                goForward: goForward,
                reload: reload
            )
        )
    }

    private func makeTab(_ url: String) -> Tab {
        Tab(
            url: URL(string: url) ?? preconditionFailure("Invalid test URL"),
            name: url,
            loadsCachedFaviconOnInit: false
        )
    }
}
