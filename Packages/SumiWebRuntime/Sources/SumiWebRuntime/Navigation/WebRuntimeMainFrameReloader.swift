import Foundation
import WebKit

/// Canonical browser-owned reload primitive. The policy is a value so an
/// exact reload can cross compositor protection without capturing a closure.
public enum WebRuntimeMainFrameReloader {
    @MainActor
    @discardableResult
    public static func reload(
        on webView: WKWebView,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> WKNavigation? {
        switch policy {
        case .standard:
            return webView.reload()
        case .fromOrigin:
            return webView.reloadFromOrigin()
        }
    }

    /// Reloads an existing committed document and materializes the exact
    /// target when WebKit reports there is no document to reload. The fallback
    /// is driven by the typed nil submission result, never URL equality.
    @MainActor
    @discardableResult
    public static func reloadOrLoad(
        _ targetURL: URL,
        on webView: WKWebView,
        policy: WebRuntimeMainFrameReloadPolicy
    ) -> WKNavigation? {
        if let navigation = reload(on: webView, policy: policy) {
            return navigation
        }

        let fallbackCachePolicy: URLRequest.CachePolicy?
        switch policy {
        case .standard:
            fallbackCachePolicy = nil
        case .fromOrigin:
            fallbackCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }
        return WebRuntimeMainFrameLoader.load(
            targetURL,
            on: webView,
            cachePolicy: fallbackCachePolicy
        )
    }
}
