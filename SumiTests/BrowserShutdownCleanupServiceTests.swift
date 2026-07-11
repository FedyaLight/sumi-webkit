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
        let coordinator = browserManager.bindTestWebViewCoordinator()
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

        service.cleanupAllTabs()
        service.cleanupAfterBrowserRuntimeDeallocation()

        XCTAssertFalse(tab.hasCurrentWebView)
        XCTAssertTrue(tab.webViewSession.allKnownWebViews.isEmpty)
        XCTAssertNil(browserManager.webViewSessions.residence(of: webView))
        XCTAssertFalse(browserManager.optionalModules.extensions.hasLoadedRuntime)
        XCTAssertFalse(browserManager.auxiliaryWindowTeardownRegistry.hasLoadedRuntime)
        withExtendedLifetime(coordinator) {}
    }
}
