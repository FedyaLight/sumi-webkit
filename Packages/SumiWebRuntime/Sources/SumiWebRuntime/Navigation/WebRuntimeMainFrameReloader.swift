import Foundation
import WebKit

public enum WebRuntimeMainFrameReloadFallback: Equatable, Sendable {
    case disallowed
    case safeOrdinaryNavigation
}

public enum WebRuntimeMainFrameReloadSubmission {
    case reloaded(WKNavigation)
    case fallbackNavigation(WKNavigation)
    case failed

    public var navigation: WKNavigation? {
        switch self {
        case .reloaded(let navigation), .fallbackNavigation(let navigation):
            navigation
        case .failed:
            nil
        }
    }
}

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

    /// Attempts the native current-item reload. A nil result stays a failure
    /// unless the caller explicitly proves this residence has no native item
    /// and admits a safe ordinary URL navigation. The result never calls that
    /// fallback a reload.
    @MainActor
    public static func reloadOrLoad(
        _ targetURL: URL,
        on webView: WKWebView,
        policy: WebRuntimeMainFrameReloadPolicy,
        fallback: WebRuntimeMainFrameReloadFallback = .disallowed
    ) -> WebRuntimeMainFrameReloadSubmission {
        if let navigation = reload(on: webView, policy: policy) {
            return .reloaded(navigation)
        }

        guard fallback == .safeOrdinaryNavigation else { return .failed }

        let fallbackCachePolicy: URLRequest.CachePolicy?
        switch policy {
        case .standard:
            fallbackCachePolicy = nil
        case .fromOrigin:
            fallbackCachePolicy = .reloadIgnoringLocalAndRemoteCacheData
        }
        guard let navigation = WebRuntimeMainFrameLoader.load(
            targetURL,
            on: webView,
            cachePolicy: fallbackCachePolicy
        ) else {
            return .failed
        }
        return .fallbackNavigation(navigation)
    }
}
