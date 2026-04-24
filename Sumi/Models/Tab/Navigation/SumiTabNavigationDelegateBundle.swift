import Foundation
import Navigation
import WebKit

@MainActor
final class SumiTabNavigationDelegateBundle {
    let distributedNavigationDelegate: DistributedNavigationDelegate
    let popupHandling: SumiPopupHandlingNavigationResponder

    private let installNavigation: SumiInstallNavigationResponder
    private let externalScheme: SumiExternalSchemeNavigationResponder
    private let downloads: SumiDownloadsNavigationResponder
    private let lifecycle: SumiTabLifecycleNavigationResponder

    init(tab: Tab) {
        self.distributedNavigationDelegate = DistributedNavigationDelegate()
        self.installNavigation = SumiInstallNavigationResponder(tab: tab)
        self.popupHandling = SumiPopupHandlingNavigationResponder(tab: tab)
        self.externalScheme = SumiExternalSchemeNavigationResponder(tab: tab)
        self.downloads = SumiDownloadsNavigationResponder(tab: tab, downloadManager: tab.browserManager?.downloadManager)
        self.lifecycle = SumiTabLifecycleNavigationResponder(tab: tab)

        distributedNavigationDelegate.setResponders(
            .strong(installNavigation),
            .strong(popupHandling),
            .strong(externalScheme),
            .strong(downloads),
            .strong(lifecycle),
            .weak(tab.findInPage)
        )
    }
}

extension Tab {
    @discardableResult
    func installNavigationDelegate(on webView: WKWebView) -> SumiTabNavigationDelegateBundle {
        if let existing = navigationDelegateBundle(for: webView) {
            webView.navigationDelegate = existing.distributedNavigationDelegate
            return existing
        }

        let bundle = SumiTabNavigationDelegateBundle(tab: self)
        navigationDelegateBundles.setObject(bundle, forKey: webView)
        webView.navigationDelegate = bundle.distributedNavigationDelegate
        return bundle
    }

    func navigationDelegateBundle(for webView: WKWebView) -> SumiTabNavigationDelegateBundle? {
        navigationDelegateBundles.object(forKey: webView)
    }

    func removeNavigationDelegateBundle(for webView: WKWebView) {
        navigationDelegateBundles.removeObject(forKey: webView)
    }

    func dispatchCreateWebView(
        from webView: WKWebView,
        _ callback: @escaping @MainActor @Sendable () -> Void
    ) {
        if let bundle = navigationDelegateBundle(for: webView) {
            bundle.distributedNavigationDelegate.dispatchCreateWebView(callback)
        } else {
            callback()
        }
    }
}
