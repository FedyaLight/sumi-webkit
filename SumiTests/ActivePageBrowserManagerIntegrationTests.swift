import SumiDomain
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ActivePageBrowserManagerIntegrationTests: XCTestCase {
    func testResolverUsesSelectedIncognitoTabAndExactWindowWebView() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupModelContainer()
            )
        )
        let webViewRuntime = browserManager.testWebViewRuntime()
        let registry = WindowRegistry()
        browserManager.windowRegistry = registry
        let window = BrowserWindowState()
        window.isIncognito = true
        window.tabManager = browserManager.tabManager
        let tab = Tab(
            url: URL(string: "https://private.example")!,
            webViewSessions: browserManager.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.ephemeralTabs = [tab]
        window.currentTabId = tab.id
        registry.register(window)
        registry.setActive(window)
        webViewRuntime.trackedWebViewAdmission.attemptAssignment(
            webView,
            to: tab,
            in: window.id,
            replaySemanticOperation: { XCTFail("Unexpected WebView deferral") }
        )

        let page = try XCTUnwrap(
            browserManager.shellRuntime.activePageResolver.resolveActiveWindow()
        )

        XCTAssertIdentical(page.windowState, window)
        XCTAssertIdentical(page.tab, tab)
        XCTAssertIdentical(page.canonicalWebView, webView)
    }

    func testResolverUsesActiveSplitMemberInsteadOfFirstGroupMember() throws {
        let browserManager = BrowserManager(
            startupPersistence: BrowserManagerStartupPersistence(
                container: try makeInMemoryStartupModelContainer()
            )
        )
        let registry = WindowRegistry()
        browserManager.windowRegistry = registry
        let firstSpace = browserManager.tabManager.spaceServices.catalog
            .createSpace(name: "First", profileId: UUID())
        let secondSpace = browserManager.tabManager.spaceServices.catalog
            .createSpace(name: "Second", profileId: UUID())
        let first = browserManager.tabManager.regularTabLifecycleOwner
            .createNewTab(url: "https://first.example", in: firstSpace)
        let active = browserManager.tabManager.regularTabLifecycleOwner
            .createNewTab(url: "https://active.example", in: secondSpace)
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(first.id), .regularTab(active.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: firstSpace.id)
            )
        )
        XCTAssertTrue(
            browserManager.tabManager.splitGroupMutations.insert(
                group,
                persist: false
            )
        )
        let window = BrowserWindowState()
        window.tabManager = browserManager.tabManager
        window.currentSpaceId = firstSpace.id
        window.currentTabId = active.id
        window.splitSelection = WindowSplitSelection(
            groupID: group.id,
            activeMemberID: .regularTab(active.id)
        )
        registry.register(window)
        registry.setActive(window)

        let page = try XCTUnwrap(
            browserManager.shellRuntime.activePageResolver.resolveActiveWindow()
        )

        XCTAssertEqual(
            browserManager.splitComposition.query.visibleTabIDs(in: window.id),
            [first.id, active.id]
        )
        XCTAssertIdentical(page.tab, active)
    }
}
