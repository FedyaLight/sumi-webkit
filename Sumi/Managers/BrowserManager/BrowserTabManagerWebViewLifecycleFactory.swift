import Foundation

@MainActor
enum BrowserTabManagerWebViewLifecycleFactory {
    static func service(for browserManager: BrowserManager) -> TabManagerWebViewLifecycleService {
        TabManagerWebViewLifecycleService(
            materializeVisibleTabWebViewIfNeeded: { [weak browserManager] tab, windowState in
                browserManager?.materializeVisibleTabWebViewIfNeeded(tab, in: windowState)
            },
            loadTab: { [weak browserManager] tab in
                browserManager?.compositorManager.loadTab(tab)
            },
            unloadTab: { [weak browserManager] tab in
                browserManager?.compositorManager.unloadTab(tab)
            },
            requireRemoveAllWebViews: { [weak browserManager] tab, closeActiveFullscreenMedia in
                guard let browserManager else { return }
                browserManager.shellRuntime.requireWebViewCoordinator().removeAllWebViews(
                    for: tab,
                    closeActiveFullscreenMedia: closeActiveFullscreenMedia
                )
            },
            windowIDsTrackingWebViews: { [weak browserManager] tabId in
                browserManager?.webViewCoordinator?.windowIDs(for: tabId) ?? []
            },
            primaryTrackedWindowId: { [weak browserManager] tabId in
                browserManager?.webViewRoutingService.primaryTrackedWindowId(for: tabId)
            },
            rebuildLiveWebViews: { [weak browserManager] tab, preferredPrimaryWindowId, url in
                if #available(macOS 15.5, *) {
                    browserManager?.webViewCoordinator?.rebuildLiveWebViews(
                        for: tab,
                        preferredPrimaryWindowId: preferredPrimaryWindowId,
                        load: url
                    )
                }
            },
            prepareTab: { [weak browserManager] tab in
                guard let browserManager else { return }
                tab.attachBrowserRuntime(TabBrowserRuntimeFactory.make(for: browserManager))
            },
            anyLiveWebView: { [weak browserManager] tab in
                browserManager?.webViewRoutingService.anyLiveWebView(for: tab)
            },
            hasUntrackedOwnedWebView: { [weak browserManager] tab in
                browserManager?.webViewRoutingService.hasUntrackedOwnedWebView(for: tab) ?? false
            }
        )
    }
}

extension TabManagerWebViewLifecycleService {
    static func live(browserManager: BrowserManager) -> TabManagerWebViewLifecycleService {
        BrowserTabManagerWebViewLifecycleFactory.service(for: browserManager)
    }
}
