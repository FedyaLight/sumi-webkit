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

    static func go(to item: WKBackForwardListItem, on webView: WKWebView) {
        guard let distance = backForwardDistance(to: item, in: webView.backForwardList),
              let navigator = webView.navigator()
        else {
            webView.go(to: item)
            return
        }

        _ = navigator.go(to: item, withExpectedNavigationType: .backForward(distance: distance))
    }

    private static func backForwardDistance(
        to item: WKBackForwardListItem,
        in list: WKBackForwardList
    ) -> Int? {
        if let backIndex = list.backList.firstIndex(where: { $0 === item }) {
            return backIndex - list.backList.count
        }
        if let forwardIndex = list.forwardList.firstIndex(where: { $0 === item }) {
            return forwardIndex + 1
        }
        return nil
    }
}
