import Foundation
import WebKit
import SumiWebRuntime

/// Broadcasts navigation state for a tab to every window displaying it:
/// URL sync, reloads (with configuration-policy rebuilds), and mute state.
@MainActor
final class WebViewNavigationBroadcastOwner {
    private let crossWindowSyncOwner: WebViewCrossWindowSyncOwner
    private let webViewRegistry: WindowWebViewRegistry
    private let tabWebViewSessionStore: TabWebViewSessionStore
    private let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
    private let primaryTrackedWindowId: @MainActor (UUID) -> UUID?
    private let rebuildLiveWebViews: @MainActor (Tab, UUID?, URL?) -> Bool

    init(
        crossWindowSyncOwner: WebViewCrossWindowSyncOwner,
        webViewRegistry: WindowWebViewRegistry,
        tabWebViewSessionStore: TabWebViewSessionStore,
        isWebViewProtectedFromCompositorMutation: @escaping @MainActor (WKWebView) -> Bool,
        primaryTrackedWindowId: @escaping @MainActor (UUID) -> UUID?,
        rebuildLiveWebViews: @escaping @MainActor (Tab, UUID?, URL?) -> Bool
    ) {
        self.crossWindowSyncOwner = crossWindowSyncOwner
        self.webViewRegistry = webViewRegistry
        self.tabWebViewSessionStore = tabWebViewSessionStore
        self.isWebViewProtectedFromCompositorMutation = isWebViewProtectedFromCompositorMutation
        self.primaryTrackedWindowId = primaryTrackedWindowId
        self.rebuildLiveWebViews = rebuildLiveWebViews
    }

    func syncTab(_ tab: Tab, to url: URL, originatingWebView: WKWebView?) {
        let tabId = tab.id
        crossWindowSyncOwner.syncTab(
            tabId,
            to: url,
            webViews: webViewRegistry.webViews(for: tabId),
            originatingWebView: originatingWebView,
            isProtected: { [isWebViewProtectedFromCompositorMutation] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            load: { webView in
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    resolvedWebView.load(URLRequest(url: url))
                }
            }
        )
    }

    func reloadTab(_ tab: Tab) {
        let reloadTargetURL = reloadTargetURL(for: tab)
        let protectionReloadWasRequired = tab.reloadPolicyStateOwner.isProtectionReloadRequired
        if tab.configurationPolicyRequiresNormalWebViewRebuild(for: reloadTargetURL) {
            if rebuildLiveWebViews(
                tab,
                primaryTrackedWindowId(tab.id),
                reloadTargetURL
            ), protectionReloadWasRequired {
                tab.noteProtectionManualReloadResult(
                    rebuiltForConfigurationPolicy: true,
                    targetURL: reloadTargetURL
                )
            }
            return
        }
        let tabId = tab.id
        crossWindowSyncOwner.reloadTab(
            tabId,
            webViews: webViewRegistry.webViews(for: tabId),
            isProtected: { [isWebViewProtectedFromCompositorMutation] webView in
                isWebViewProtectedFromCompositorMutation(webView)
            },
            reload: { webView in
                tab.performMainFrameNavigationAfterHydrationIfNeeded(
                    on: webView
                ) { resolvedWebView in
                    resolvedWebView.reload()
                }
            }
        )
    }

    @discardableResult
    func reloadTab(_ tab: Tab, in windowId: UUID) -> Bool {
        guard let webView = webViewRegistry.webView(for: tab.id, in: windowId) else {
            return false
        }
        if isWebViewProtectedFromCompositorMutation(webView) {
            RuntimeDiagnostics.protectedWebViewTrace(
                "skipReloadProtected webView=\(ObjectIdentifier(webView)) tab=\(tab.id.uuidString.prefix(8)) window=\(windowId.uuidString.prefix(8))"
            )
            return false
        }
        tab.performMainFrameNavigationAfterHydrationIfNeeded(
            on: webView
        ) { resolvedWebView in
            resolvedWebView.reload()
        }
        return true
    }

    func setMuteState(_ muted: Bool, for tabId: UUID) {
        crossWindowSyncOwner.setMuteState(
            muted,
            for: tabId,
            windowWebViews: webViewRegistry.windowWebViews(for: tabId)
        )
    }

    private func reloadTargetURL(for tab: Tab) -> URL {
        let store = tabWebViewSessionStore
        store.promoteLocalSessionIfNeeded(
            tabId: tab.id,
            localSession: tab.webViewOwnershipOwner.localSession
        )
        if let sessionURL = store.session(for: tab.id).currentWebView?.url
            ?? store.untrackedWebView(for: tab.id)?.url
            ?? store.parkedWebView(for: tab.id)?.url {
            return sessionURL
        }
        return tab.url
    }
}
