import Foundation
import WebKit

extension Tab {
    func targetFindWebView() -> FocusableWKWebView? {
        let targetWebView: WKWebView?
        if let activeWindowId = findInPageRuntime.activeWindowId() {
            targetWebView = findInPageRuntime.webView(id, activeWindowId)
        } else {
            targetWebView = existingWebView
        }

        return targetWebView as? FocusableWKWebView
    }
}
