import Navigation
import WebKit

@MainActor
enum SumiWebViewNavigator {
    static func goBack(on webView: WKWebView) {
        guard let backItem = webView.backForwardList.backItem,
              let navigator = webView.navigator()
        else {
            guard canUseNativeFallback(on: webView) else { return }
            webView.goBack()
            return
        }

        performBrowserOwnedHistoryNavigation(
            to: backItem,
            on: webView,
            navigator: navigator,
            expectedNavigationType: .backForward(distance: -1)
        )
    }

    static func goForward(on webView: WKWebView) {
        guard let forwardItem = webView.backForwardList.forwardItem,
              let navigator = webView.navigator()
        else {
            guard canUseNativeFallback(on: webView) else { return }
            webView.goForward()
            return
        }

        performBrowserOwnedHistoryNavigation(
            to: forwardItem,
            on: webView,
            navigator: navigator,
            expectedNavigationType: .backForward(distance: 1)
        )
    }

    static func go(to item: WKBackForwardListItem, on webView: WKWebView) {
        guard let distance = backForwardDistance(to: item, in: webView.backForwardList),
              let navigator = webView.navigator()
        else {
            guard canUseNativeFallback(on: webView) else { return }
            webView.go(to: item)
            return
        }

        performBrowserOwnedHistoryNavigation(
            to: item,
            on: webView,
            navigator: navigator,
            expectedNavigationType: .backForward(distance: distance)
        )
    }

    private static func performBrowserOwnedHistoryNavigation(
        to item: WKBackForwardListItem,
        on webView: WKWebView,
        navigator: Navigator,
        expectedNavigationType: NavigationType
    ) {
        let tab = (webView as? FocusableWKWebView)?.owningTab
        let submissionLease = tab?.beginBrowserOwnedHistoryNavigation(
            to: item.url,
            on: webView
        )
        guard let expectedNavigation = navigator.go(
            to: item,
            withExpectedNavigationType: expectedNavigationType
        ) else {
            if let tab, let submissionLease {
                tab.failBrowserOwnedHistoryNavigation(
                    on: webView,
                    matching: submissionLease
                )
            }
            return
        }
        guard let tab else { return }
        precondition(
            tab.mainFrameSubmission.bindSubmittedLoad(
                on: webView,
                navigationID: expectedNavigation.stableIdentifier,
                navigationLifetime: expectedNavigation.identityLifetime,
                matching: submissionLease
            ),
            "Browser-owned history navigation lost its exact submission"
        )
    }

    private static func canUseNativeFallback(on webView: WKWebView) -> Bool {
        guard (webView as? FocusableWKWebView)?.owningTab != nil else {
            return true
        }
        assertionFailure(
            "Normal-tab history navigation requires DistributedNavigationDelegate"
        )
        return false
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
