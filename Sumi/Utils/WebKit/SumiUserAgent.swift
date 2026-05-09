import WebKit

enum SumiUserAgent {
    @MainActor
    static func apply(to webView: WKWebView) {
        webView.customUserAgent = nil
    }
}
