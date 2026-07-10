import Foundation
import WebKit

extension Tab {
    func targetFindWebView(in windowId: UUID?) -> FocusableWKWebView? {
        let targetWebView: WKWebView?
        if let windowId {
            targetWebView = navigationRuntime.findInPageRuntime.webView(id, windowId)
        } else {
            targetWebView = resolvedCurrentWebView()
        }

        return targetWebView?.sumiActivePresentationWebView as? FocusableWKWebView
    }
}
