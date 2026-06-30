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

    func testPermissionSurfaceOwnerUsesNarrowContextWithoutTab() throws {
        let tabId = UUID()
        let profile = Profile(
            id: UUID(uuidString: "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee")!,
            name: "Permission Context",
            icon: "person"
        )
        let currentURL = URL(string: "https://visible.example/page")!
        let committedURL = URL(string: "https://committed.example/main")!
        let targetURL = URL(string: "https://next.example/")!
        var pageGeneration = 0
        var lifecycleEvents: [SumiPermissionLifecycleEvent] = []

        let owner = TabPermissionSurfaceOwner(
            context: TabPermissionSurfaceOwner.Context(
                tabId: tabId,
                currentURL: { currentURL },
                resolveProfile: { profile },
                isActiveTab: { true },
                isVisibleTab: { false },
                pageIdentity: {
                    let tabIdString = tabId.uuidString.lowercased()
                    let generation = String(pageGeneration)
                    return TabExtensionPageIdentity(
                        tabId: tabIdString,
                        pageGeneration: generation,
                        pageId: "\(tabIdString):\(generation)"
                    )
                },
                committedMainDocumentURL: { committedURL },
                isCurrentPage: { pageId, pageGenerationSnapshot in
                    let tabIdString = tabId.uuidString.lowercased()
                    let generation = String(pageGeneration)
                    return pageId == "\(tabIdString):\(generation)"
                        && pageGenerationSnapshot == generation
                },
                invalidateCurrentPageForWebViewReplacement: {
                    pageGeneration += 1
                },
                handlePermissionLifecycleEvent: { event in
                    lifecycleEvents.append(event)
                },
                isActiveGlancePreviewSurface: { _ in false }
            )
        )
        let webView = WKWebView()

        let permissionContext = try XCTUnwrap(owner.externalSchemeContext(for: webView))

        XCTAssertEqual(permissionContext.tabId, tabId.uuidString.lowercased())
        XCTAssertEqual(permissionContext.pageId, "\(tabId.uuidString.lowercased()):0")
        XCTAssertEqual(permissionContext.profilePartitionId, profile.id.uuidString.lowercased())
        XCTAssertEqual(permissionContext.committedURL, committedURL)
        XCTAssertEqual(permissionContext.visibleURL, currentURL)
        XCTAssertEqual(permissionContext.mainFrameURL, committedURL)
        XCTAssertTrue(permissionContext.isActiveTab)
        XCTAssertFalse(permissionContext.isVisibleTab)
        XCTAssertTrue(try XCTUnwrap(permissionContext.isCurrentPage)())

        owner.handleNormalTabPermissionNavigation(to: targetURL)
        owner.invalidateCurrentPageForWebViewReplacement(reason: "test-replacement")

        XCTAssertFalse(try XCTUnwrap(permissionContext.isCurrentPage)())
        XCTAssertEqual(owner.currentPageId(), "\(tabId.uuidString.lowercased()):1")
        XCTAssertEqual(
            lifecycleEvents,
            [
                .mainFrameNavigation(
                    pageId: "\(tabId.uuidString.lowercased()):0",
                    tabId: tabId.uuidString.lowercased(),
                    profilePartitionId: profile.id.uuidString,
                    targetURL: targetURL,
                    reason: "normal-tab-main-frame-navigation"
                ),
                .webViewReplaced(
                    pageId: "\(tabId.uuidString.lowercased()):0",
                    tabId: tabId.uuidString.lowercased(),
                    profilePartitionId: profile.id.uuidString,
                    reason: "test-replacement"
                ),
            ]
        )
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
