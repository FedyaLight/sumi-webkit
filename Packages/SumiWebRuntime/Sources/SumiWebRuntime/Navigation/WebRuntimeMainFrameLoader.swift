import Foundation
import WebKit

/// One production-shaped loading primitive for browser-owned main frames.
/// Local files require an explicit read-access scope; network and extension
/// documents share the canonical request policy.
public enum WebRuntimeMainFrameLoader {
    @MainActor
    @discardableResult
    public static func load(
        _ targetURL: URL,
        on webView: WKWebView,
        cachePolicy: URLRequest.CachePolicy? = nil
    ) -> WKNavigation? {
        if targetURL.isFileURL {
            return webView.loadFileURL(
                targetURL,
                allowingReadAccessTo: targetURL.deletingLastPathComponent()
            )
        }
        var request = WebRuntimeNavigationRequestFactory.navigationRequest(
            for: targetURL
        )
        if let cachePolicy {
            request.cachePolicy = cachePolicy
        }
        return webView.load(request)
    }
}
