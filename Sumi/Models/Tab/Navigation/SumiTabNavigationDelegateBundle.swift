import AppKit
import Combine
import Foundation
import Navigation
import WebKit

@MainActor
final class SumiTabNavigationDelegateAdapter {
    private let distributedNavigationDelegate: DistributedNavigationDelegate
    private let popupHandling: SumiPopupHandlingNavigationResponder

    private let glanceNavigation: SumiGlanceNavigationResponder
    private let glanceNavigationAdapter: SumiNavigationResponderAdapter
    private let installNavigation: SumiInstallNavigationResponder
    private let installNavigationAdapter: SumiNavigationResponderAdapter
    private let internalSurfaceNavigation: SumiInternalSurfaceNavigationResponder
    private let internalSurfaceNavigationAdapter: SumiNavigationResponderAdapter
    private let popupHandlingAdapter: SumiNavigationResponderAdapter
    private let externalScheme: SumiExternalSchemeNavigationResponder
    private let externalSchemeAdapter: SumiNavigationResponderAdapter
    private let downloads: SumiDownloadsNavigationResponder
    private let downloadsAdapter: SumiNavigationResponderAdapter
    private let scriptAttachment: SumiTabScriptAttachmentNavigationResponder
    private let scriptAttachmentAdapter: SumiNavigationResponderAdapter
    private let autoplayPolicy: SumiAutoplayPolicyNavigationResponder
    private let autoplayPolicyAdapter: SumiNavigationResponderAdapter
    private let lifecycle: SumiTabLifecycleNavigationResponder
    private let lifecycleAdapter: SumiNavigationResponderAdapter
    private let inlineUIExtensionResources: SafariExtensionInlineUINavigationResponder
    private let inlineUIExtensionResourcesAdapter: SumiNavigationResponderAdapter
    private let findInPageAdapter: SumiNavigationResponderAdapter

    init(tab: Tab) {
        self.distributedNavigationDelegate = DistributedNavigationDelegate()
        self.glanceNavigation = SumiGlanceNavigationResponder(tab: tab)
        self.glanceNavigationAdapter = SumiNavigationResponderAdapter(target: glanceNavigation)
        self.installNavigation = SumiInstallNavigationResponder(tab: tab)
        self.installNavigationAdapter = SumiNavigationResponderAdapter(target: installNavigation)
        self.internalSurfaceNavigation = SumiInternalSurfaceNavigationResponder(tab: tab)
        self.internalSurfaceNavigationAdapter = SumiNavigationResponderAdapter(target: internalSurfaceNavigation)
        self.popupHandling = SumiPopupHandlingNavigationResponder(tab: tab)
        self.popupHandlingAdapter = SumiNavigationResponderAdapter(target: popupHandling)
        self.externalScheme = SumiExternalSchemeNavigationResponder(
            tab: tab,
            permissionBridge: tab.navigationDelegateRuntime.externalSchemePermissionBridge()
        )
        self.externalSchemeAdapter = SumiNavigationResponderAdapter(target: externalScheme)
        self.downloads = SumiDownloadsNavigationResponder(
            tab: tab,
            downloadManager: tab.navigationDelegateRuntime.downloadManager()
        )
        self.downloadsAdapter = SumiNavigationResponderAdapter(target: downloads)
        self.scriptAttachment = SumiTabScriptAttachmentNavigationResponder(tab: tab)
        self.scriptAttachmentAdapter = SumiNavigationResponderAdapter(target: scriptAttachment)
        self.autoplayPolicy = SumiAutoplayPolicyNavigationResponder(tab: tab)
        self.autoplayPolicyAdapter = SumiNavigationResponderAdapter(target: autoplayPolicy)
        self.lifecycle = SumiTabLifecycleNavigationResponder(tab: tab)
        self.lifecycleAdapter = SumiNavigationResponderAdapter(target: lifecycle)
        self.inlineUIExtensionResources = SafariExtensionInlineUINavigationResponder()
        self.inlineUIExtensionResourcesAdapter = SumiNavigationResponderAdapter(
            target: inlineUIExtensionResources
        )
        self.findInPageAdapter = SumiNavigationResponderAdapter(target: tab.findInPage)

        distributedNavigationDelegate.setResponders(
            .strong(glanceNavigationAdapter),
            .strong(installNavigationAdapter),
            .strong(internalSurfaceNavigationAdapter),
            .strong(popupHandlingAdapter),
            .strong(externalSchemeAdapter),
            .strong(downloadsAdapter),
            .strong(scriptAttachmentAdapter),
            .strong(autoplayPolicyAdapter),
            .strong(lifecycleAdapter),
            .strong(inlineUIExtensionResourcesAdapter),
            .strong(findInPageAdapter)
        )
    }

    func install(on webView: WKWebView) {
        webView.navigationDelegate = distributedNavigationDelegate
    }

    func isInstalled(on webView: WKWebView) -> Bool {
        webView.navigationDelegate === distributedNavigationDelegate
    }

    func dispatchCreateWebView(_ callback: @escaping @MainActor @Sendable () -> Void) {
        distributedNavigationDelegate.dispatchCreateWebView(callback)
    }

    func createWebView(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        popupHandling.createWebView(
            from: webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures
        )
    }

    func createWebViewAsync(
        from webView: WKWebView,
        with configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) async -> WKWebView? {
        await popupHandling.createWebViewAsync(
            from: webView,
            with: configuration,
            for: navigationAction,
            windowFeatures: windowFeatures
        )
    }

    @discardableResult
    func consumeNativeContextMenuRequest(
        from item: NSMenuItem,
        perform handler: @escaping @MainActor (WKNavigationAction) -> Void
    ) -> Bool {
        popupHandling.consumeNativeContextMenuRequest(from: item, perform: handler)
    }

    func hasResponder<T: AnyObject>(_ type: T.Type) -> Bool {
        distributedNavigationDelegate.getResponders().contains { responder in
            guard let adapter = responder as? SumiNavigationResponderAdapter else {
                return false
            }
            return adapter.isAdapting(type)
        }
    }

    func hasInlineUIExtensionResourceResponderInChain() -> Bool {
        hasResponder(SafariExtensionInlineUINavigationResponder.self)
    }
}

extension Tab {
    @discardableResult
    func installNavigationDelegate(on webView: WKWebView) -> SumiTabNavigationDelegateAdapter {
        if let existing = navigationDelegateBundle(for: webView) {
            existing.install(on: webView)
            bindWebViewInteractionEvents(on: webView)
            return existing
        }

        let bundle = SumiTabNavigationDelegateAdapter(tab: self)
        navigationDelegateBundles.setObject(bundle, forKey: webView)
        bundle.install(on: webView)
        bindWebViewInteractionEvents(on: webView)
        return bundle
    }

    func navigationDelegateBundle(for webView: WKWebView) -> SumiTabNavigationDelegateAdapter? {
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
            bundle.dispatchCreateWebView(callback)
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
