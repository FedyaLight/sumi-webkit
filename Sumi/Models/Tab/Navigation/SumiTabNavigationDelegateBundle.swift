import Combine
import Foundation
import Navigation
import WebKit

@MainActor
final class SumiTabNavigationDelegateBundle {
    let distributedNavigationDelegate: DistributedNavigationDelegate
    let popupHandling: SumiPopupHandlingNavigationResponder

    private let installNavigation: SumiInstallNavigationResponder
    private let installNavigationAdapter: SumiNavigationResponderAdapter
    private let externalScheme: SumiExternalSchemeNavigationResponder
    private let externalSchemeAdapter: SumiNavigationResponderAdapter
    private let downloads: SumiDownloadsNavigationResponder
    private let scriptAttachment: SumiTabScriptAttachmentNavigationResponder
    private let scriptAttachmentAdapter: SumiNavigationResponderAdapter
    private let autoplayPolicy: SumiAutoplayPolicyNavigationResponder
    private let autoplayPolicyAdapter: SumiNavigationResponderAdapter
    private let lifecycle: SumiTabLifecycleNavigationResponder

    init(tab: Tab) {
        self.distributedNavigationDelegate = DistributedNavigationDelegate()
        self.installNavigation = SumiInstallNavigationResponder(tab: tab)
        self.installNavigationAdapter = SumiNavigationResponderAdapter(target: installNavigation)
        self.popupHandling = SumiPopupHandlingNavigationResponder(tab: tab)
        self.externalScheme = SumiExternalSchemeNavigationResponder(
            tab: tab,
            permissionBridge: tab.browserManager?.externalSchemePermissionBridge
        )
        self.externalSchemeAdapter = SumiNavigationResponderAdapter(target: externalScheme)
        self.downloads = SumiDownloadsNavigationResponder(tab: tab, downloadManager: tab.browserManager?.downloadManager)
        self.scriptAttachment = SumiTabScriptAttachmentNavigationResponder(tab: tab)
        self.scriptAttachmentAdapter = SumiNavigationResponderAdapter(target: scriptAttachment)
        self.autoplayPolicy = SumiAutoplayPolicyNavigationResponder(tab: tab)
        self.autoplayPolicyAdapter = SumiNavigationResponderAdapter(target: autoplayPolicy)
        self.lifecycle = SumiTabLifecycleNavigationResponder(tab: tab)

        distributedNavigationDelegate.setResponders(
            .strong(installNavigationAdapter),
            .strong(popupHandling),
            .strong(externalSchemeAdapter),
            .strong(downloads),
            .strong(scriptAttachmentAdapter),
            .strong(autoplayPolicyAdapter),
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
            bindWebViewInteractionEvents(on: webView)
            return existing
        }

        let bundle = SumiTabNavigationDelegateBundle(tab: self)
        navigationDelegateBundles.setObject(bundle, forKey: webView)
        webView.navigationDelegate = bundle.distributedNavigationDelegate
        bindWebViewInteractionEvents(on: webView)
        return bundle
    }

    func navigationDelegateBundle(for webView: WKWebView) -> SumiTabNavigationDelegateBundle? {
        navigationDelegateBundles.object(forKey: webView)
    }

    func removeNavigationDelegateBundle(for webView: WKWebView) {
        navigationDelegateBundles.removeObject(forKey: webView)
        webViewInteractionCancellables.removeValue(forKey: ObjectIdentifier(webView))
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

    private func bindWebViewInteractionEvents(on webView: WKWebView) {
        guard let webView = webView as? FocusableWKWebView else { return }
        let webViewID = ObjectIdentifier(webView)
        guard webViewInteractionCancellables[webViewID] == nil else { return }

        webViewInteractionCancellables[webViewID] = webView.interactionEventsPublisher
            .sink { [weak self] interactionEvent in
                MainActor.assumeIsolated {
                    self?.recordWebViewInteraction(interactionEvent)
                }
            }
    }
}
