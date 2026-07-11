import WebKit
import XCTest

@testable import Sumi

@MainActor
final class BrowserShutdownCleanupServiceTests: XCTestCase {
    func testTabCleanupOrderIsStableAndDeduplicatedAcrossAllResidences() {
        let essential = Tab(name: "Essential", loadsCachedFaviconOnInit: false)
        let regular = Tab(name: "Regular", loadsCachedFaviconOnInit: false)
        let ephemeral = Tab(name: "Ephemeral", loadsCachedFaviconOnInit: false)

        let result = BrowserShutdownCleanupService.uniqueTabsForCleanup(
            essential: [essential, regular],
            all: [regular],
            ephemeral: [ephemeral, essential]
        )

        XCTAssertEqual(result.map(\.id), [essential.id, regular.id, ephemeral.id])
    }

    func testCleanupReleasesTabWebViewsWithoutLoadingOptionalExtensionRuntime() {
        let browserManager = BrowserManager()
        let webViewRuntime = browserManager.testWebViewRuntime()
        let space = browserManager.tabManager.spaceServices.catalog.createSpace(
            name: "Shutdown"
        )
        let tab = browserManager.tabManager.regularTabLifecycleOwner.createNewTab(
            url: "https://shutdown.example/page",
            in: space,
            activate: true
        )
        let webView = WKWebView()
        tab.replaceUntrackedWebView(webView)
        let service = browserManager.shutdownCleanupService

        XCTAssertTrue(tab.hasCurrentWebView)
        XCTAssertFalse(browserManager.optionalModules.extensions.hasLoadedRuntime)
        XCTAssertFalse(browserManager.auxiliaryWindowTeardownRegistry.hasLoadedRuntime)
        XCTAssertTrue(webViewRuntime.ownershipQuery.owns(webView, for: tab))

        service.cleanupAllTabs()
        XCTAssertFalse(tab.hasCurrentWebView)
        XCTAssertNil(browserManager.webViewSessions.residence(of: webView))

        let lateWebView = WKWebView()
        tab.replaceUntrackedWebView(lateWebView)
        XCTAssertTrue(webViewRuntime.ownershipQuery.owns(lateWebView, for: tab))

        service.cleanupAfterBrowserRuntimeDeallocation()
        service.cleanupAllTabs()
        service.cleanupAfterBrowserRuntimeDeallocation()

        XCTAssertFalse(tab.hasCurrentWebView)
        XCTAssertTrue(tab.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertNil(browserManager.webViewSessions.residence(of: webView))
        XCTAssertNil(browserManager.webViewSessions.residence(of: lateWebView))
        XCTAssertFalse(webViewRuntime.ownershipQuery.owns(lateWebView, for: tab))
        XCTAssertFalse(browserManager.optionalModules.extensions.hasLoadedRuntime)
        XCTAssertFalse(browserManager.auxiliaryWindowTeardownRegistry.hasLoadedRuntime)
        withExtendedLifetime((webViewRuntime, webView, lateWebView)) {}
    }
}
