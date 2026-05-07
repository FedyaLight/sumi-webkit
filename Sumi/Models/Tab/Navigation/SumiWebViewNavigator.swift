import Navigation
import WebKit

@MainActor
enum SumiWebViewNavigator {
    static func goBack(on webView: WKWebView) {
        guard let backItem = webView.backForwardList.backItem,
              let navigator = webView.navigator()
        else {
            webView.goBack()
            return
        }

        _ = navigator.go(to: backItem, withExpectedNavigationType: .backForward(distance: -1))
    }

    static func goForward(on webView: WKWebView) {
        guard let forwardItem = webView.backForwardList.forwardItem,
              let navigator = webView.navigator()
        else {
            webView.goForward()
            return
        }

        _ = navigator.go(to: forwardItem, withExpectedNavigationType: .backForward(distance: 1))
    }
}
