import AppKit
import Foundation
import WebKit

enum SumiFaviconResolver {
    static func cacheKey(for url: URL) -> String? {
        SumiFaviconLookupKey.cacheKey(for: url)
    }

    static func image(for url: URL, webView: WKWebView? = nil) async -> NSImage? {
        let manager = await MainActor.run { SumiFaviconSystem.shared.manager }
        return await manager.handleFaviconLinks([], documentUrl: url, webView: webView)?.image
    }
}
