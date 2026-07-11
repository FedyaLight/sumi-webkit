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
        let coordinator = browserManager.bindTestWebViewCoordinator()
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
        let webView = WKWebView()
        window.ephemeralTabs = [tab]
        window.currentTabId = tab.id
        registry.register(window)
        registry.setActive(window)
        coordinator.ownershipService.assign(webView, to: tab, in: window.id)

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
        let group = try XCTUnwrap(SplitGroup.make(
            tabIds: [first.id, active.id],
            layoutKind: .vertical,
            activeTabId: active.id,
            host: .regular(spaceId: firstSpace.id),
            members: [
                SplitGroupMember(
                    tabId: first.id,
                    pinId: nil,
                    origin: .regular(spaceId: firstSpace.id, index: 0)
                ),
                SplitGroupMember(
                    tabId: active.id,
                    pinId: nil,
                    origin: .regular(spaceId: secondSpace.id, index: 0)
                ),
            ]
        ))
        browserManager.tabManager.splitGroupStructureOwner.upsertSplitGroup(group)
        let window = BrowserWindowState()
        window.tabManager = browserManager.tabManager
        window.currentSpaceId = firstSpace.id
        window.currentTabId = active.id
        registry.register(window)
        registry.setActive(window)

        let page = try XCTUnwrap(
            browserManager.shellRuntime.activePageResolver.resolveActiveWindow()
        )

        XCTAssertEqual(browserManager.splitManager.visibleTabIds(for: window.id), [first.id, active.id])
        XCTAssertIdentical(page.tab, active)
    }
}
