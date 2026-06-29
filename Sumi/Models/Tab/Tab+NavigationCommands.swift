import Foundation
import WebKit

extension Tab {
    // MARK: - URL Navigation Commands

    func loadURL(_ newURL: URL) {
        self.url = newURL
        beginLoadingPresentationIfNeeded()

        guard _webView != nil else {
            setupWebView()
            return
        }

        let rebuiltForConfigurationPolicy = rebuildNormalWebViewForConfigurationPolicyIfNeeded(
            targetURL: newURL,
            reason: "Tab.loadURL"
        )
        resetPlaybackActivity()
        // The muted part of audioState is preserved to maintain the user's mute preference.

        if newURL.isFileURL {
            // Grant read access to the containing directory for local resources
            let directoryURL = newURL.deletingLastPathComponent()
            if let webView = _webView {
                performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
                    on: webView,
                    waitForContentBlockingAssets: rebuiltForConfigurationPolicy
                ) { resolvedWebView in
                    resolvedWebView.loadFileURL(
                        newURL,
                        allowingReadAccessTo: directoryURL
                    )
                }
            }
        } else {
            let request = Self.navigationCommandURLRequest(for: newURL)
            if let webView = _webView {
                performMainFrameNavigationAfterContentBlockingAssetsIfNeeded(
                    on: webView,
                    waitForContentBlockingAssets: rebuiltForConfigurationPolicy
                ) { resolvedWebView in
                    resolvedWebView.load(request)
                }
            }
        }

        applyCachedFaviconOrPlaceholder(for: newURL)
    }

    func loadURL(_ urlString: String) {
        guard let newURL = URL(string: urlString) else {
            RuntimeDiagnostics.emit("Invalid URL: \(urlString)")
            return
        }
        loadURL(newURL)
    }

    /// Navigate to a new URL with proper search engine normalization
    func navigateToURL(_ input: String) {
        let settings = sumiSettings ?? browserManager?.sumiSettings
        let template = settings?.resolvedSearchEngineTemplate ?? SearchProvider.google.queryTemplate
        let normalizedUrl = normalizeURL(input, queryTemplate: template)

        guard let validURL = URL(string: normalizedUrl) else {
            RuntimeDiagnostics.emit("Invalid URL after normalization: \(input) -> \(normalizedUrl)")
            return
        }

        loadURL(validURL)
    }

    nonisolated static func navigationCommandURLRequest(for url: URL) -> URLRequest {
        var request = URLRequest(url: url)
        request.cachePolicy = navigationCommandCachePolicy(for: url)
        request.timeoutInterval = 30.0
        return request
    }

    nonisolated private static func navigationCommandCachePolicy(for url: URL) -> URLRequest.CachePolicy {
        let scheme = url.scheme?.lowercased() ?? ""
        if scheme == "webkit-extension" || scheme == "safari-web-extension" {
            return .reloadIgnoringLocalCacheData
        }
        return .returnCacheDataElseLoad
    }
}
