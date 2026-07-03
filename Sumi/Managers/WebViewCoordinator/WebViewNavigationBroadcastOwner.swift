import Foundation
import WebKit

/// Broadcasts navigation state for a tab to every window displaying it:
/// URL sync, reloads (with configuration-policy rebuilds), and mute state.
@MainActor
final class WebViewNavigationBroadcastOwner {
    struct Dependencies {
        let crossWindowSyncOwner: WebViewCrossWindowSyncOwner
        let webViewRegistry: WindowWebViewRegistry
        let isWebViewProtectedFromCompositorMutation: @MainActor (WKWebView) -> Bool
        let rebuildLiveWebViews: @MainActor (Tab, UUID?, URL?) -> Bool
    }

    private let dependencies: Dependencies

    init(dependencies: Dependencies) {
        self.dependencies = dependencies
    }

    func syncTab(_ tab: Tab, to url: URL, originatingWebView: WKWebView?) {
        let tabId = tab.id
        dependencies.crossWindowSyncOwner.syncTab(
            tabId,
            to: url,
            webViews: dependencies.webViewRegistry.webViews(for: tabId),
            originatingWebView: originatingWebView,
            isProtected: { [dependencies] webView in
                dependencies.isWebViewProtectedFromCompositorMutation(webView)
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
        let reloadTargetURL = tab.existingWebView?.url ?? tab.url
        let protectionReloadWasRequired = tab.reloadPolicyStateOwner.isProtectionReloadRequired
        if tab.configurationPolicyRequiresNormalWebViewRebuild(for: reloadTargetURL) {
            if dependencies.rebuildLiveWebViews(
                tab,
                tab.primaryWindowId,
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
        dependencies.crossWindowSyncOwner.reloadTab(
            tabId,
            webViews: dependencies.webViewRegistry.webViews(for: tabId),
            isProtected: { [dependencies] webView in
                dependencies.isWebViewProtectedFromCompositorMutation(webView)
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
        guard let webView = dependencies.webViewRegistry.webView(for: tab.id, in: windowId) else {
            return false
        }
        if dependencies.isWebViewProtectedFromCompositorMutation(webView) {
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
        dependencies.crossWindowSyncOwner.setMuteState(
            muted,
            for: tabId,
            windowWebViews: dependencies.webViewRegistry.windowWebViews(for: tabId)
        )
    }
}

extension WebViewNavigationBroadcastOwner.Dependencies {
    @MainActor
    static func live(coordinator: WebViewCoordinator) -> Self {
        Self(
            crossWindowSyncOwner: coordinator.crossWindowSyncOwner,
            webViewRegistry: coordinator.webViewRegistry,
            isWebViewProtectedFromCompositorMutation: { [weak coordinator] webView in
                coordinator?.isWebViewProtectedFromCompositorMutation(webView) ?? false
            },
            rebuildLiveWebViews: { [weak coordinator] tab, preferredPrimaryWindowId, url in
                coordinator?.rebuildLiveWebViews(
                    for: tab,
                    preferredPrimaryWindowId: preferredPrimaryWindowId,
                    load: url
                ) ?? false
            }
        )
    }
}
