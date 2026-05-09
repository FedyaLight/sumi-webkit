import WebKit

enum SumiUserAgent {
    static let safariCompatibleApplicationNameForUserAgent =
        "Version/26.0 Safari/605.1.15"

    @MainActor
    static func apply(to webView: WKWebView) {
        webView.customUserAgent = nil
    }
}
