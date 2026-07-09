import Foundation
import WebKit

extension Tab {
    // MARK: - URL Navigation Commands

    func loadURL(_ newURL: URL) {
        navigationCommandOwner.loadURL(newURL, for: self)
    }

    func loadURL(_ urlString: String) {
        navigationCommandOwner.loadURL(urlString, for: self)
    }

    public func loadURL(
        _ url: URL,
        resolvedWebView: @escaping @MainActor @Sendable () -> WKWebView?,
        reason: String
    ) {
        navigationCommandOwner.loadURL(
            url,
            for: self,
            resolvedWebView: resolvedWebView,
            reason: reason
        )
    }


    /// Navigate to a new URL with proper search engine normalization
    func navigateToURL(_ input: String) {
        navigationCommandOwner.navigateToURL(input, for: self)
    }

    nonisolated static func navigationCommandURLRequest(for url: URL) -> URLRequest {
        TabNavigationCommandOwner.navigationCommandURLRequest(for: url)
    }
}
