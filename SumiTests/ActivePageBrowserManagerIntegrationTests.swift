import SumiDomain
import WebKit
import XCTest

@testable import Sumi

@MainActor
final class ActivePageBrowserManagerIntegrationTests: XCTestCase {
    func testResolverUsesSelectedIncognitoTabAndExactWindowWebView() throws {
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupDatabase()
            )
        )
        let webViewRuntime = browserManager.testWebViewRuntime()
        let window = BrowserWindowState()
        window.isIncognito = true
        browserManager.tabResidenceAuthority.establishResidenceSession(on: window)
        let tab = Tab(
            url: URL(string: "https://private.example")!,
            webViewSessions: browserManager.webViewSessions,
            loadsCachedFaviconOnInit: false
        )
        let webView = FocusableWKWebView()
        webView.owningTab = tab
        window.replaceEphemeralTabs([tab])
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
        let registry = WindowRegistry()
        let browserManager = BrowserManager(
            windowRegistry: registry,
            startupPersistence: BrowserManagerStartupPersistence(database: try makeInMemoryStartupDatabase()
            )
        )
        let firstSpace = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "First",
            profileID: UUID()
        )
        let secondSpace = installTestSpace(
            in: browserManager.spaceStateOwner,
            name: "Second",
            profileID: UUID()
        )
        let first = browserManager.regularTabLifecycleOwner
            .createNewTab(url: "https://first.example", in: firstSpace)
        let active = browserManager.regularTabLifecycleOwner
            .createNewTab(url: "https://active.example", in: secondSpace)
        let group = try XCTUnwrap(
            SplitGroup.make(
                members: [.regularTab(first.id), .regularTab(active.id)],
                layoutKind: .vertical,
                container: .regularTabs(spaceId: firstSpace.id)
            )
        )
        XCTAssertTrue(
            browserManager.splitGroupMutations.insert(
                group,
                persist: false
            )
        )
        let window = BrowserWindowState()
        browserManager.tabResidenceAuthority.establishResidenceSession(on: window)
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
            browserManager.splitWindowContext.query.visibleTabIDs(in: window.id),
            [first.id, active.id]
        )
        XCTAssertIdentical(page.tab, active)
    }
}
