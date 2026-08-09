import Foundation
import WebKit

@MainActor
enum SumiWebKitPageStateAdapter {
    private static let webProcessIdentifierSelector =
        NSSelectorFromString("_webProcessIdentifier")

    static func sessionStateData(from webView: WKWebView) -> Data? {
        SumiWKSessionStateData(webView) as Data?
    }

    static func restoreSessionState(
        _ data: Data,
        to webView: WKWebView
    ) -> WKNavigation? {
        SumiRestoreWKSessionState(webView, data)
    }

    static func webProcessIdentifier(for webView: WKWebView) -> pid_t? {
        guard webView.responds(to: webProcessIdentifierSelector) else {
            return nil
        }
        typealias WebProcessIdentifierImplementation =
            @convention(c) (AnyObject, Selector) -> pid_t
        let implementation = webView.method(
            for: webProcessIdentifierSelector
        )
        let function = unsafeBitCast(
            implementation,
            to: WebProcessIdentifierImplementation.self
        )
        let processID = function(webView, webProcessIdentifierSelector)
        return processID > 0 ? processID : nil
    }
}
