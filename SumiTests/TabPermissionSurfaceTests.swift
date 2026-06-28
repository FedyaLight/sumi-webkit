import WebKit
import XCTest

@testable import Sumi

@MainActor
final class TabPermissionSurfaceTests: XCTestCase {
    func testPermissionPageIdUsesTabIdAndDocumentGeneration() {
        let tab = makeTab()

        XCTAssertEqual(
            tab.currentPermissionPageId(),
            "\(tab.id.uuidString.lowercased()):0"
        )

        tab.invalidateCurrentPermissionPageForWebViewReplacement(reason: "test-webview-replacement")

        XCTAssertEqual(
            tab.currentPermissionPageId(),
            "\(tab.id.uuidString.lowercased()):1"
        )
    }

    func testPermissionContextsFailClosedWithoutResolvedProfile() {
        let tab = makeTab(browserManager: nil)
        let webView = WKWebView()

        XCTAssertNil(tab.popupPermissionTabContext(for: webView))
        XCTAssertNil(tab.externalSchemePermissionTabContext(for: webView))
    }

    func testExternalSchemeCurrentPageClosureInvalidatesAfterWebViewReplacement() throws {
        let browserManager = BrowserManager()
        let tab = makeTab(browserManager: browserManager)
        let webView = WKWebView()
        let context = try XCTUnwrap(tab.externalSchemePermissionTabContext(for: webView))

        XCTAssertEqual(context.pageId, tab.currentPermissionPageId())
        XCTAssertEqual(context.navigationOrPageGeneration, "0")
        XCTAssertEqual(context.profilePartitionId, browserManager.currentProfile?.id.uuidString.lowercased())
        XCTAssertTrue(try XCTUnwrap(context.isCurrentPage)())

        tab.invalidateCurrentPermissionPageForWebViewReplacement(reason: "test-webview-replacement")

        XCTAssertFalse(try XCTUnwrap(context.isCurrentPage)())
        XCTAssertEqual(tab.currentPermissionPageId(), "\(tab.id.uuidString.lowercased()):1")
    }

    func testPermissionSurfaceStateAndPopupContextUseActiveVisibleWindowSurface() throws {
        let browserManager = BrowserManager()
        let tab = makeManagedTab(in: browserManager)
        let (windowRegistry, windowState) = registerWindow(in: browserManager, selecting: tab)
        let webView = WKWebView()

        XCTAssertTrue(tab.permissionRequestSurfaceState(for: webView).isActive)
        XCTAssertFalse(tab.permissionRequestSurfaceState(for: webView).isVisible)

        tab.primaryWindowId = windowState.id

        let context = try XCTUnwrap(tab.popupPermissionTabContext(for: webView))
        XCTAssertTrue(tab.permissionRequestIsActiveSurface(for: webView))
        XCTAssertTrue(tab.permissionRequestIsVisibleSurface(for: webView))
        XCTAssertTrue(context.isActiveTab)
        XCTAssertTrue(context.isVisibleTab)
        XCTAssertEqual(context.pageId, tab.currentPermissionPageId())
        XCTAssertEqual(context.visibleURL, tab.url)
        XCTAssertEqual(context.mainFrameURL, tab.url)
        withExtendedLifetime(windowRegistry) { /* no-op */ }
    }

    private func makeTab(browserManager: BrowserManager? = nil) -> Tab {
        Tab(
            url: URL(string: "https://example.com/page")!,
            name: "Example",
            browserManager: browserManager,
            loadsCachedFaviconOnInit: false
        )
    }

    private func makeManagedTab(in browserManager: BrowserManager) -> Tab {
        let space = browserManager.tabManager.currentSpace
            ?? browserManager.tabManager.createSpace(name: "Permission Surface Tests")
        return browserManager.tabManager.createNewTab(
            url: "https://example.com/page",
            in: space,
            activate: true
        )
    }

    @discardableResult
    private func registerWindow(
        in browserManager: BrowserManager,
        selecting tab: Tab
    ) -> (WindowRegistry, BrowserWindowState) {
        let windowRegistry = browserManager.windowRegistry ?? WindowRegistry()
        browserManager.windowRegistry = windowRegistry

        let windowState = BrowserWindowState()
        windowState.tabManager = browserManager.tabManager
        windowState.currentTabId = tab.id
        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return (windowRegistry, windowState)
    }
}
