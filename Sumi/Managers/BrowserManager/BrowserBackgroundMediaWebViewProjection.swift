import Foundation
import WebKit

@MainActor
final class BrowserBackgroundMediaWebViewProjection {
    private let ownership: WebViewOwnershipQuery

    init(ownership: WebViewOwnershipQuery) {
        self.ownership = ownership
    }

    func entries(for tab: Tab) -> [(windowID: UUID?, webView: WKWebView)] {
        ownership.windowIDs(for: tab.id).compactMap { windowID in
            ownership.webView(for: tab.id, in: windowID).map {
                (windowID: Optional(windowID), webView: $0)
            }
        }
    }
}
