import AppKit
import Foundation
import UserScript
import WebKit

struct SumiDiscoveredFaviconLink: Hashable, Sendable {
    let url: URL
    let relation: String
    let type: String?

    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.url == rhs.url
            && lhs.relation == rhs.relation
            && lhs.type == rhs.type
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(url)
        hasher.combine(relation)
        hasher.combine(type)
    }
}

actor SumiFaviconResolver {
    static let shared = SumiFaviconResolver()

    nonisolated static func cacheKey(for url: URL) -> String? {
        SumiFaviconLookupKey.cacheKey(for: url)
    }

    func image(for url: URL, webView: WKWebView? = nil) async -> NSImage? {
        let manager = await MainActor.run { SumiFaviconSystem.shared.manager }
        return await manager.handleFaviconLinks([], documentUrl: url, webView: webView)?.image
    }

    func image(
        for documentURL: URL,
        discoveredLinks: [SumiDiscoveredFaviconLink],
        webView: WKWebView? = nil
    ) async -> NSImage? {
        let manager = await MainActor.run { SumiFaviconSystem.shared.manager }
        return await manager.handleFaviconLinks(
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
                type: $0.type
            )
        }
    }
}
