import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserURLBarContextOwnerTests: XCTestCase {
    func testNavigationHistorySelectedURLUsesWindowSpaceAndSelectsOpenedTab() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let source = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example",
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = source.id
        let targetURL = URL(string: "https://selected.example/page")!

        harness.browserManager.urlBarBundle.contextOwner
            .navigationHistoryContext(for: harness.windowState)
            .openURLInNewTab(targetURL, true, source)

        let opened = harness.browserManager.tabManager.regularTabCollectionOwner.tabs(in: harness.primarySpace)
            .first { $0.url == targetURL }
        guard let opened else {
            XCTFail("Expected navigation history context to open selected URL")
            return
        }
        XCTAssertEqual(opened.spaceId, harness.primarySpace.id)
        XCTAssertEqual(harness.windowState.currentTabId, opened.id)
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.primarySpace.id)
    }

    func testNavigationHistoryBackgroundURLInsertsAfterSourceWithoutChangingSelection() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let source = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example",
            in: harness.primarySpace,
            activate: false
        )
        let trailing = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://trailing.example",
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = source.id
        let targetURL = URL(string: "https://background.example/page")!

        harness.browserManager.urlBarBundle.contextOwner
            .navigationHistoryContext(for: harness.windowState)
            .openURLInNewTab(targetURL, false, source)

        let tabs = harness.browserManager.tabManager.regularTabCollectionOwner.tabs(in: harness.primarySpace)
        let opened = tabs.first { $0.url == targetURL }
        guard let opened else {
            XCTFail("Expected navigation history context to open background URL")
            return
        }
        XCTAssertEqual(harness.windowState.currentTabId, source.id)
        XCTAssertEqual(tabs.map(\.id), [source.id, opened.id, trailing.id])
    }

    func testNavigationHistoryCurrentURLLoadsCurrentTabInBoundWindow() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let source = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://source.example",
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = source.id
        let targetURL = URL(string: "https://current.example/page")!

        harness.browserManager.urlBarBundle.contextOwner
            .navigationHistoryContext(for: harness.windowState)
            .openURLInCurrentTab(targetURL, source)

        XCTAssertEqual(source.url, targetURL)
        XCTAssertEqual(harness.windowState.currentTabId, source.id)
        XCTAssertEqual(harness.windowState.currentSpaceId, harness.primarySpace.id)
    }

    func testURLBarContextReflectsFreshSnapshotState() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let request = SumiBookmarkEditorPresentationRequest(
            windowID: harness.windowState.id,
            tabID: UUID()
        )

        harness.browserManager.zoomStateRevision = 41
        harness.browserManager.bookmarkEditorPresentationRequest = request

        var context = harness.browserManager.urlBarBundle.contextOwner.urlBarContext
        XCTAssertEqual(context.zoom.stateRevision, 41)
        XCTAssertEqual(context.bookmarkEditorPresentationRequest, request)

        harness.browserManager.zoomStateRevision = 42
        harness.browserManager.bookmarkEditorPresentationRequest = nil

        context = harness.browserManager.urlBarBundle.contextOwner.urlBarContext
        XCTAssertEqual(context.zoom.stateRevision, 42)
        XCTAssertNil(context.bookmarkEditorPresentationRequest)
    }

    func testNavigationToolbarReloadUsesWindowScopedRefreshPath() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let tab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://reload.example",
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = tab.id
        let webView = EmptyReloadRecordingWebView()
        _ = tab.installNavigationDelegate(on: webView)
        harness.browserManager.webViewOwnershipService?.registerTrackedWebView(
            webView,
            for: tab,
            in: harness.windowState.id
        )

        harness.browserManager.urlBarBundle.contextOwner
            .navigationToolbarContext(for: harness.windowState)
            .reload(tab)

        XCTAssertEqual(webView.reloadCount, 1)
        XCTAssertEqual(webView.loadedRequests.map(\.url), [tab.url])
        XCTAssertTrue(webView.didSubmitFallbackLoad)
        webView.stopLoading()
    }

    func testURLBarReloadPageUsesWindowScopedRefreshPath() {
        removePersistedWindowSession()
        defer { removePersistedWindowSession() }

        let harness = makeHarness()
        let tab = harness.browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://urlbar-reload.example",
            in: harness.primarySpace,
            activate: false
        )
        harness.windowState.currentTabId = tab.id
        let webView = EmptyReloadRecordingWebView()
        _ = tab.installNavigationDelegate(on: webView)
        harness.browserManager.webViewOwnershipService?.registerTrackedWebView(
            webView,
            for: tab,
            in: harness.windowState.id
        )

        harness.browserManager.urlBarBundle.contextOwner.urlBarContext.reloadPage(
            tab,
            harness.windowState,
            "BrowserURLBarContextOwnerTests.reload"
        )

        XCTAssertEqual(webView.reloadCount, 1)
        XCTAssertEqual(webView.loadedRequests.map(\.url), [tab.url])
        XCTAssertTrue(webView.didSubmitFallbackLoad)
        webView.stopLoading()
    }

    private func makeHarness() -> Harness {
        let browserManager = BrowserManager()
        let windowRegistry = WindowRegistry()
        let profile = Profile(name: "Primary")
        let primarySpace = Space(name: "Primary", profileId: profile.id)
        let windowState = BrowserWindowState()

        browserManager.profileManager.profiles = [profile]
        browserManager.currentProfile = profile
        browserManager.windowRegistry = windowRegistry
        browserManager.bindTestWebViewCoordinator()
        browserManager.tabManager.spaceStateOwner.replaceSpaces([primarySpace])
        browserManager.tabManager.spaceStateOwner.replaceCurrentSpace(primarySpace)

        windowState.tabManager = browserManager.tabManager
        windowState.currentSpaceId = primarySpace.id
        windowState.currentProfileId = profile.id

        windowRegistry.register(windowState)
        windowRegistry.setActive(windowState)

        return Harness(
            browserManager: browserManager,
            windowState: windowState,
            primarySpace: primarySpace
        )
    }

    private func removePersistedWindowSession() {
        UserDefaults.standard.removeObject(forKey: BrowserManager.lastWindowSessionKey)
    }
}

@MainActor
private final class EmptyReloadRecordingWebView: WKWebView {
    private(set) var reloadCount = 0
    private(set) var loadedRequests: [URLRequest] = []
    private(set) var didSubmitFallbackLoad = false

    override func reload() -> WKNavigation? {
        reloadCount += 1
        return nil
    }

    override func load(_ request: URLRequest) -> WKNavigation? {
        loadedRequests.append(request)
        let navigation = super.load(request)
        didSubmitFallbackLoad = navigation != nil
        return navigation
    }
}

@MainActor
private struct Harness {
    let browserManager: BrowserManager
    let windowState: BrowserWindowState
    let primarySpace: Space
}
