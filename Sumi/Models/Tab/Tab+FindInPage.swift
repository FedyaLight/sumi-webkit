import Foundation
import WebKit

extension Tab {
    func targetFindWebView() -> FocusableWKWebView? {
        let targetWebView: WKWebView?
        if let browserManager,
           let activeWindowId = browserManager.windowRegistry?.activeWindow?.id
        {
            targetWebView = browserManager.getWebView(for: id, in: activeWindowId)
        } else {
            targetWebView = existingWebView
        }

        return targetWebView as? FocusableWKWebView
    }
}
