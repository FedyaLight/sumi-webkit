import AppKit
import Combine
import Foundation
import Navigation
import WebKit
import SumiDomain

@MainActor
final class SumiTabNavigationDelegateAdapter {
    private let navigationResponderChain: DistributedNavigationDelegate
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
    private let gpc: SumiGPCNavigationResponder
    private let gpcAdapter: SumiNavigationResponderAdapter
    private let autoplayPolicy: SumiAutoplayPolicyNavigationResponder
    private let autoplayPolicyAdapter: SumiNavigationResponderAdapter
    private let lifecycle: SumiTabLifecycleNavigationResponder
    private let lifecycleAdapter: SumiNavigationResponderAdapter
    private let inlineUIExtensionResources: SafariExtensionInlineUINavigationResponder
    private let inlineUIExtensionResourcesAdapter: SumiNavigationResponderAdapter
    private let findInPageAdapter: SumiNavigationResponderAdapter

    init(tab: Tab) {
        self.navigationResponderChain = DistributedNavigationDelegate()
        self.glanceNavigation = SumiGlanceNavigationResponder()
        self.glanceNavigationAdapter = SumiNavigationResponderAdapter(target: glanceNavigation)
        self.installNavigation = SumiInstallNavigationResponder(tab: tab)
        self.installNavigationAdapter = SumiNavigationResponderAdapter(target: installNavigation)
        self.internalSurfaceNavigation = SumiInternalSurfaceNavigationResponder()
        self.internalSurfaceNavigationAdapter = SumiNavigationResponderAdapter(target: internalSurfaceNavigation)
        self.popupHandling = SumiPopupHandlingNavigationResponder(
            tab: tab,
            permissions: tab.navigationRuntime.popupPermissionEvaluator,
            extensionRequests:
                tab.navigationRuntime.extensionPopupRequestConsumer,
            extensionTabs: tab.navigationRuntime.extensionExternalTabOpening,
            webPopups: tab.navigationRuntime.physicalWebPopupOpening,
            childTabs: tab.navigationRuntime.webKitChildTabOpening,
            childWindows: tab.navigationRuntime.webKitChildWindowOpening
        )
        self.popupHandlingAdapter = SumiNavigationResponderAdapter(target: popupHandling)
        self.externalScheme = SumiExternalSchemeNavigationResponder(
            tab: tab,
            permissionBridge: tab.navigationRuntime.navigationDelegateRuntime.externalSchemePermissionBridge()
        )
        self.externalSchemeAdapter = SumiNavigationResponderAdapter(target: externalScheme)
        self.downloads = SumiDownloadsNavigationResponder(
            tab: tab,
            downloadManager: tab.navigationRuntime.navigationDelegateRuntime.downloadManager()
        )
        self.downloadsAdapter = SumiNavigationResponderAdapter(target: downloads)
        self.scriptAttachment = SumiTabScriptAttachmentNavigationResponder(tab: tab)
        self.scriptAttachmentAdapter = SumiNavigationResponderAdapter(target: scriptAttachment)
        self.gpc = SumiGPCNavigationResponder(tab: tab)
        self.gpcAdapter = SumiNavigationResponderAdapter(target: gpc)
        self.autoplayPolicy = SumiAutoplayPolicyNavigationResponder(
            tab: tab,
            autoplayPolicy: tab.navigationRuntime.navigationDelegateRuntime.autoplayPolicy
        )
        self.autoplayPolicyAdapter = SumiNavigationResponderAdapter(target: autoplayPolicy)
        self.lifecycle = tab.makeMainFrameLifecycleResponder()
        self.lifecycleAdapter = SumiNavigationResponderAdapter(target: lifecycle)
        self.inlineUIExtensionResources = SafariExtensionInlineUINavigationResponder()
        self.inlineUIExtensionResourcesAdapter = SumiNavigationResponderAdapter(
            target: inlineUIExtensionResources
        )
        self.findInPageAdapter = SumiNavigationResponderAdapter(target: tab.findInPage)

        navigationResponderChain.setResponders(
            .strong(glanceNavigationAdapter),
            .strong(installNavigationAdapter),
            .strong(internalSurfaceNavigationAdapter),
            .strong(popupHandlingAdapter),
            .strong(externalSchemeAdapter),
            .strong(downloadsAdapter),
            .strong(scriptAttachmentAdapter),
            .strong(gpcAdapter),
            .strong(autoplayPolicyAdapter),
            .strong(lifecycleAdapter),
            .strong(inlineUIExtensionResourcesAdapter),
            .strong(findInPageAdapter)
        )
    }

    func install(on webView: WKWebView) {
        lifecycleAdapter.bind(to: webView)
        webView.navigationDelegate = navigationResponderChain
    }

    func isInstalled(on webView: WKWebView) -> Bool {
        webView.navigationDelegate === navigationResponderChain
    }

    func dispatchCreateWebView(_ callback: @escaping @MainActor @Sendable () -> Void) {
        navigationResponderChain.dispatchCreateWebView(callback)
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

    func hasResponder<T: AnyObject>(_ type: T.Type) -> Bool {
        navigationResponderChain.getResponders().contains { responder in
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
            return existing
        }

        let bundle = SumiTabNavigationDelegateAdapter(tab: self)
        navigationRuntime.navigationDelegateBundles.setObject(bundle, forKey: webView)
        bundle.install(on: webView)
        return bundle
    }

    func navigationDelegateBundle(for webView: WKWebView) -> SumiTabNavigationDelegateAdapter? {
        navigationRuntime.navigationDelegateBundles.object(forKey: webView)
    }

    func removeNavigationDelegateBundle(for webView: WKWebView) {
        navigationRuntime.navigationDelegateBundles.removeObject(forKey: webView)
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

}
