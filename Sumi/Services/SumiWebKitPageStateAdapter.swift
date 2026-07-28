import Foundation
import WebKit

@MainActor
enum SumiWebKitPageStateAdapter {
    private static let webProcessIdentifierSelector =
        NSSelectorFromString("_webProcessIdentifier")

    static func interactionStateData(from webView: WKWebView) -> Data? {
        webView.interactionState as? Data
    }

    static func restoreInteractionState(
        _ data: Data,
        to webView: WKWebView
    ) {
        webView.interactionState = data
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
