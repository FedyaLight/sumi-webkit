import Foundation
import SumiDomain
import SumiWebRuntime
import WebKit

/// The single construction seam for browser-owned tabs. Every tab created by
/// a production `TabManager` starts on the same WebView session repository as
/// the browser kernel; runtime attachment is no longer responsible for moving
/// ownership out of a tab-local bootstrap repository.
@MainActor
struct TabFactory {
    let webViewSessions: WebViewSessionRepository
    let faviconService: any BrowserFaviconServicing
    let faviconCapabilities: BrowserFaviconCapabilities
    let visitedLinkStore: any BrowserVisitedLinkStoreManaging

    func makeTab(
        id: UUID = UUID(),
        url: URL = SumiSurface.emptyTabURL,
        name: String = "New Tab",
        favicon: String = "globe",
        spaceId: UUID? = nil,
        index: Int = 0,
        existingWebView: WKWebView? = nil,
        loadsCachedFaviconOnInit: Bool = true
    ) -> Tab {
        Tab(
            id: id,
            url: url,
            name: name,
            favicon: favicon,
            spaceId: spaceId,
            index: index,
            existingWebView: existingWebView,
            webViewSessions: webViewSessions,
            loadsCachedFaviconOnInit: loadsCachedFaviconOnInit,
            faviconService: faviconService,
            faviconCapabilities: faviconCapabilities,
            visitedLinkStore: visitedLinkStore
        )
    }
}
