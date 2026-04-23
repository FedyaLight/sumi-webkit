import AppKit
import Foundation
import WebKit

struct SumiDiscoveredFaviconLink: Hashable, Sendable {
    let url: URL
    let relation: String
    let type: String?
}

actor SumiFaviconResolver {
    static let shared = SumiFaviconResolver()

    nonisolated static func cacheKey(for url: URL) -> String? {
        SumiFaviconLookupKey.cacheKey(for: url)
    }

    func image(for url: URL, webView: WKWebView? = nil) async -> NSImage? {
        let manager = await MainActor.run { SumiFaviconSystem.shared.manager }
        return await manager.loadFavicon(for: url, webView: webView)?.image
    }

    func image(
        for documentURL: URL,
        discoveredLinks: [SumiDiscoveredFaviconLink],
        webView: WKWebView? = nil
    ) async -> NSImage? {
        let manager = await MainActor.run { SumiFaviconSystem.shared.manager }
        return await manager.handleLiveFaviconLinks(
            Self.faviconLinks(from: discoveredLinks),
            documentUrl: documentURL,
            webView: webView
        )?.image
    }

    nonisolated static func faviconLinks(
        from discoveredLinks: [SumiDiscoveredFaviconLink]
    ) -> [FaviconUserScript.FaviconLink] {
        discoveredLinks.map {
            FaviconUserScript.FaviconLink(
                href: $0.url,
                rel: $0.relation,
                sizes: nil,
                type: $0.type
            )
        }
    }

    func resetTransientState() async {
        await MainActor.run {
            SumiFaviconSystem.shared.manager.clearAll()
        }
    }
}
